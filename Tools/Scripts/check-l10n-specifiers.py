#!/usr/bin/env python3
"""Compare format specifiers between en and every locale for Spiral's own strings (question 305).

For each locale's Untranslated.strings / .stringsdict: every key en has must carry the same specifiers
(positional ones may be reordered); each plural category must carry the specifiers of en's `other`
(only ar and cy may drop the number in zero/one/two). Prints problems and exits 1 if there are any.
Usage: Tools/Scripts/check-l10n-specifiers.py [locale ...]
"""
import json, os, plistlib, re, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'ElementX', 'Resources', 'Localizations')
SPEC = re.compile(r'%(?:\d+\$)?(?:#@\w+@|l{0,2}[@dfsuxi]|%)')
CATEGORIES = ('zero', 'one', 'two', 'few', 'many', 'other')


def specs(text):
    return sorted(SPEC.findall(text))


def strings(locale):
    path = os.path.join(ROOT, f'{locale}.lproj', 'Untranslated.strings')
    if not os.path.exists(path):
        return {}
    out = subprocess.run(['plutil', '-convert', 'json', '-o', '-', path], capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out.strip() else {}


def plurals(locale):
    path = os.path.join(ROOT, f'{locale}.lproj', 'Untranslated.stringsdict')
    if not os.path.exists(path):
        return {}
    with open(path, 'rb') as handle:
        return plistlib.load(handle)


def check(locale, en_strings, en_plurals):
    problems = []
    for key, value in strings(locale).items():
        if key in en_strings and specs(value) != specs(en_strings[key]):
            problems.append(f'{key}: en {specs(en_strings[key])}, {locale} {specs(value)}')
    for key, entry in plurals(locale).items():
        source = en_plurals.get(key)
        if source is None:
            continue
        if specs(entry.get('NSStringLocalizedFormatKey', '')) != specs(source['NSStringLocalizedFormatKey']):
            problems.append(f'{key}: format key {entry.get("NSStringLocalizedFormatKey")!r}')
        for variable, rules in source.items():
            if not isinstance(rules, dict):
                continue
            mine = entry.get(variable)
            if not isinstance(mine, dict) or 'other' not in mine:
                problems.append(f'{key}.{variable}: missing or no other')
                continue
            expected = specs(rules['other'])
            for category in CATEGORIES:
                if category in mine and specs(mine[category]) != expected:
                    if locale in ('ar', 'cy') and category in ('zero', 'one', 'two') and not specs(mine[category]):
                        continue
                    problems.append(f'{key}.{variable}.{category}: en {expected}, {locale} {specs(mine[category])}')
    return problems


def main():
    en_strings, en_plurals = strings('en'), plurals('en')
    locales = sys.argv[1:] or sorted(d[:-6] for d in os.listdir(ROOT) if d.endswith('.lproj') and d != 'en.lproj')
    failed = 0
    for locale in locales:
        problems = check(locale, en_strings, en_plurals)
        print(f'{locale}: {"OK" if not problems else f"{len(problems)} mismatches"}')
        for problem in problems:
            print('   ', problem)
        failed += bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
