#!/usr/bin/env python3
"""Validate native translation tables against compiler-extracted localization keys."""
from pathlib import Path
import json,plistlib,re,subprocess,sys

root=Path(__file__).resolve().parent.parent
resources=root/'Resources'
def table(language):
 path=resources/(language+'.lproj')/'Localizable.strings'
 output=subprocess.check_output(['/usr/bin/plutil','-convert','json','-o','-',str(path)])
 value=json.loads(output)
 assert isinstance(value,dict) and all(isinstance(k,str) and isinstance(v,str) and v for k,v in value.items())
 return value
english=table('en');chinese=table('zh-Hans');traditional=table('zh-Hant')
assert set(english)==set(chinese)==set(traditional),'Translation tables have different keys'
# Only conversions emitted by these source strings; an ordinary percent followed
# by English prose is not a printf conversion (for example, "100% target").
formats=re.compile(r'%(?:\d+\$)?(?:\.\d+)?(?:lld|ld|lf|u|d|f|@|%)')
for key,value in english.items():
 assert chinese[key]==key,'Chinese source text changed: '+key
 for language,translation in [('en',value),('zh-Hant',traditional[key])]:
  assert formats.findall(key)==formats.findall(translation),'Format mismatch in '+language+': '+key
 assert not re.search('[\u4e00-\u9fff]',value),'Untranslated English value: '+key
plural=plistlib.loads((resources/'en.lproj/Localizable.stringsdict').read_bytes())
assert set(plural)<=set(english),'Plural table introduces unknown source keys'
for key,entry in plural.items():
 names=[name for name in entry if name!='NSStringLocalizedFormatKey']
 assert len(names)==1 and entry['NSStringLocalizedFormatKey']=='%#@'+names[0]+'@'
 rule=entry[names[0]]
 assert rule['NSStringFormatSpecTypeKey']=='NSStringPluralRuleType' and rule['NSStringFormatValueTypeKey']=='lld'
 for form in ['one','other']:
  assert formats.findall(rule[form])==formats.findall(key),'Plural placeholder mismatch: '+key
  assert not re.search('[\u4e00-\u9fff]',rule[form]),'Untranslated plural: '+key
phrases={}
for language in ['en','zh-Hans','zh-Hant']:
 path=resources/(language+'.lproj')/'AppShortcuts.strings'
 phrases[language]=json.loads(subprocess.check_output(['/usr/bin/plutil','-convert','json','-o','-',str(path)]))
assert set(phrases['en'])==set(phrases['zh-Hans'])==set(phrases['zh-Hant'])
source=(root/'Sources/OpenCharge/Intents.swift').read_text()
source_phrases={value.replace('\\(.applicationName)','${applicationName}') for value in re.findall(r'phrases: \["([^"\n]*)"\]',source)}
assert source_phrases==set(phrases['en']),'App Shortcut phrase coverage mismatch'
for key,value in phrases['en'].items():
 for language in phrases:
  assert key.count('${applicationName}')==phrases[language][key].count('${applicationName}')==1
 assert phrases['zh-Hans'][key]==key and not re.search('[\u4e00-\u9fff]',value)
extracted=set()
# Swift's localization emitter does not report these legacy Foundation calls.
# Accept only literal keys in the fixed call form; never evaluate Swift code or
# silently skip a dynamic lookup when validating the full translation tables.
foundation_keys=set()
literal_lookup=re.compile(r'\bNSLocalizedString\s*\(\s*("(?:[^"\\]|\\.)*")\s*,\s*comment:\s*""\s*\)')
for path in (root/'Sources').rglob('*.swift'):
 text=path.read_text()
 matches=list(literal_lookup.finditer(text))
 assert len(matches)==len(re.findall(r'\bNSLocalizedString\s*\(',text)),'Unvalidated Foundation lookup: '+str(path)
 for match in matches:
  key=json.loads(match.group(1))
  assert '\\(' not in key,'Interpolated Foundation key: '+str(path)
  if re.search('[\u4e00-\u9fff]',key):foundation_keys.add(key)
assert not foundation_keys-set(english),'Missing Foundation translations: '+repr(sorted(foundation_keys-set(english)))
for folder in sys.argv[1:]:
 for path in Path(folder).glob('*.stringsdata'):
  data=json.loads(path.read_text())
  for entry in data.get('tables',{}).get('Localizable',[]):
   key=entry['key']
   if re.search('[\u4e00-\u9fff]',key):extracted.add(key)
if sys.argv[1:]:
 assert extracted,'Compiler extraction produced no Chinese source keys'
 assert not extracted-set(english),'Missing translations: '+repr(sorted(extracted-set(english)))
 assert not set(english)-(extracted|foundation_keys),'Translation keys lack source coverage: '+repr(sorted(set(english)-(extracted|foundation_keys)))
print('PASS native localization tables:',len(english),'keys in three languages, matching Chinese source and format placeholders;',len(extracted),'compiler-extracted and',len(foundation_keys),'literal Foundation keys covered')
