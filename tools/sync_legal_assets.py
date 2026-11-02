"""Generate local-only draft legal assets. No deployment or network operation."""
import html
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'assets/legal/policies.json'
catalog = json.loads(source.read_text(encoding='utf-8'))
assert catalog['status'] == 'draft' and catalog['effective_at'] is None
assert len(catalog['policies']) == 8
for policy in catalog['policies']:
    assert all(policy.get(key) for key in ['key', 'title_ar', 'title_en', 'ar', 'en'])
for target in [root.parent / 'arena_owner/assets/legal/policies.json', root.parent / 'playon_admin/public/legal/policies.json']:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(source.read_bytes())
public = root.parent / 'playon_admin/public/legal'
for lang in ['ar', 'en']:
    direction = 'rtl' if lang == 'ar' else 'ltr'
    warning = 'مسودة غير نافذة — لم تُنشر أو تُعتمد قانونيًا' if lang == 'ar' else 'DRAFT — NOT EFFECTIVE OR LEGALLY APPROVED'
    links = ''.join(f'<li><a href="{p["key"]}-{lang}.html">{html.escape(p["title_"+lang])}</a></li>' for p in catalog['policies'])
    for p in catalog['policies']:
        text = ''.join('<p>'+html.escape(x)+'</p>' for x in p[lang].split('\n\n'))
        content = f'<!doctype html><html lang="{lang}" dir="{direction}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>{html.escape(p["title_"+lang])}</title><style>body{{font-family:system-ui,sans-serif;max-width:56rem;margin:auto;padding:1.5rem;line-height:1.9}}aside{{padding:1rem;background:#fff3cd}}a{{color:#153e5c}}p{{white-space:pre-wrap}}</style><aside>{warning} · {catalog["version"]}</aside><nav><a href="{p["key"]}-{"en" if lang=="ar" else "ar"}.html">العربية / English</a></nav><h1>{html.escape(p["title_"+lang])}</h1>{text}<nav><ul>{links}</ul></nav></html>'
        (public/f'{p["key"]}-{lang}.html').write_text(content, encoding='utf-8')
    (public/f'index-{lang}.html').write_text(f'<!doctype html><html lang="{lang}" dir="{direction}"><meta charset="utf-8"><title>Arena Legal</title><h1>{warning}</h1><ul>{links}</ul></html>',encoding='utf-8')
# Full reusable bilingual text artifact; no guessed domain or contact data.
report = '# نصوص سياسات Arena — مسودات غير نافذة\n\nالإصدار: '+catalog['version']+'\n'
for p in catalog['policies']:
    report += '\n## '+p['title_ar']+'\n\n'+p['ar']+'\n\n### '+p['title_en']+'\n\n'+p['en']+'\n'
(root/'ARENA_LEGAL_POLICY_TEXTS_2026_10_26.md').write_text(report,encoding='utf-8')
print('8 bilingual drafts synchronized; 16 public-page files generated locally; no publishing.')
