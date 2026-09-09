"""Inspect PDF streams and Illustrator round-trip output; not just screenshots."""
import io, json, sys, hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageCms
from pypdf import PdfReader

root = Path(sys.argv[1])
record = json.loads((root / 'export-result.json').read_text(encoding='utf-8'))
checks = []
def check(value, name):
    if not value: raise AssertionError(name)
    checks.append(name)
def obj(v): return v.get_object() if hasattr(v, 'get_object') else v
def color_space(image): return obj(image['/ColorSpace'])
def cmyk_pixels(image):
    data = np.frombuffer(image.get_data(), np.uint8)
    cs = color_space(image)
    if isinstance(cs, list) and cs[0] == '/Indexed':
        palette = obj(cs[3])
        palette = palette.get_data() if hasattr(palette, 'get_data') else bytes(palette)
        return np.frombuffer(palette, np.uint8).reshape(-1, 4)[data]
    return data.reshape(-1, 4)
def alpha(image): return np.frombuffer(obj(image['/SMask']).get_data(), np.uint8)

pdf = PdfReader(root / '测试立牌.pdf')
check(len(pdf.pages) == 6, 'six PDF pages')
expected = record['pdf']['audit']['pageMm']
for i, p in enumerate(pdf.pages):
    mm = [float(p.mediabox.width)*25.4/72, float(p.mediabox.height)*25.4/72]
    target = expected if i < 5 else [297, 210]
    check(max(abs(a-b) for a,b in zip(mm,target)) < .001, f'page {i+1} millimetres')
source = Image.open(root / 'source.png').convert('RGBA')
w,h = source.size
art = obj(pdf.pages[0]['/Resources']['/XObject']['/Art'])
check([art['/Width'],art['/Height']] == [w,h], 'original artwork pixel dimensions')
cs = color_space(art)
check(cs[0] == '/ICCBased' and obj(cs[1])['/N'] == 4, 'four-channel CMYK ICC image')
icc = obj(cs[1]).get_data()
profile = ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(icc))).strip()
check('Swop Standard' in profile, 'identified SWOP profile, not an assumed name')
check(hashlib.sha256(icc).hexdigest() == record['pdf']['audit']['iccSha256'], 'embedded ICC checksum')
check(np.array_equal(alpha(art), np.array(source)[:,:,3].ravel()), 'artwork original alpha preserved')
white = obj(pdf.pages[1]['/Resources']['/XObject']['/White'])
check(color_space(white) == '/DeviceCMYK', 'white uses DeviceCMYK')
check(np.all(cmyk_pixels(white) == [0,0,0,255]), 'white is exactly C0 M0 Y0 K100')
original_mask = np.frombuffer((root/'white-alpha.bin').read_bytes(),np.uint8)
check(np.array_equal(alpha(white),original_mask), 'PDF retains exact completed white mask')
check([white['/Width'],white['/Height']] == [w,h], 'white mask uses original pixels')
if record['pdf']['audit']['strokeCount']:
    original_alpha = np.array(source)[:,:,3].ravel()
    check(np.count_nonzero((original_alpha>0)&(original_alpha<255))>0,'fixture includes fractional source alpha')
    check(np.count_nonzero((original_alpha==0)&(original_mask>0))>0,'brush adds coverage into transparent hole')
else:
    a=np.array(source)[:,:,3].astype(np.uint16).ravel()
    threshold=int(record['pdf']['audit']['sourceSettings']['threshold']*2.55+.5)
    expected_white=np.minimum(255,a*255//threshold).astype(np.uint8)
    check(np.array_equal(expected_white,original_mask),'automatic white threshold formula')
ai=PdfReader(root/'测试立牌.ai')
check(len(ai.pages)==2,'AI has two PDF-compatible artboards')
check('/Illustrator' in ai.pages[0]['/PieceInfo'],'AI has Illustrator private data')
audit=json.loads((root/'测试立牌.ai.reopen.json').read_text(encoding='utf-8-sig'))
check(audit['ok'] and audit['artboards']==2,'Illustrator reopen inspection passed')
proof=PdfReader(root/'测试立牌.ai.white-proof.pdf')
found=False
for ref in proof.pages[0]['/Resources']['/XObject'].values():
    im=obj(ref)
    if im.get('/Subtype')!='/Image' or '/SMask' not in im: continue
    try:
        coverage=alpha(im); pixels=cmyk_pixels(im)
    except Exception: continue
    if len(coverage)==len(original_mask) and np.array_equal(coverage,original_mask):
        if np.all(pixels[coverage>0]==[0,0,0,255]): found=True
check(found,'Illustrator round-trip preserves every mask byte and active K100 pixel')
result={'ok':True,'checks':checks,'sourcePixels':[w,h],'pdfICC':profile,'aiICC':audit['icc'],'whiteMaskSha256':hashlib.sha256(original_mask).hexdigest()}
(root/'structural-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
