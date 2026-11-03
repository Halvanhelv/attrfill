"""HTTP acceptance probe. Run ONLY against an isolated throwaway app/database.

python3 script/readiness_http.py http://127.0.0.1:18018 tmp/readiness/http.json
"""
import concurrent.futures
import csv
import html
import http.cookiejar
import io
import json
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = sys.argv[1].rstrip('/')
OUTPUT = Path(sys.argv[2])
target = urllib.parse.urlparse(BASE)
if target.scheme != 'http' or target.hostname != '127.0.0.1' or target.port != 18018:
    raise SystemExit('This probe writes test records; use the isolated app on 127.0.0.1:18018')
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
results = []


def request(path, data=None, method=None, headers=None, opener=client):
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers or {})
    try:
        with opener.open(req, timeout=90) as response:
            return response.status, response.read(), response.geturl()
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.geturl()


def check(name, fn):
    started = time.perf_counter()
    try:
        detail = fn()
        result = {'check': name, 'ok': True, 'seconds': time.perf_counter() - started, 'detail': detail}
    except Exception as error:
        result = {'check': name, 'ok': False, 'seconds': time.perf_counter() - started,
                  'error': type(error).__name__ + ': ' + str(error)}
    results.append(result)
    print(json.dumps(result, ensure_ascii=False), flush=True)
    OUTPUT.write_text(json.dumps(results, indent=2, ensure_ascii=False))


def token():
    status, body, _ = request('/')
    assert status == 200
    found = re.search(rb'<meta name="csrf-token" content="([^"]+)"', body)
    assert found, 'Missing CSRF token'
    return html.unescape(found[1].decode())


def form(path, fields, method='POST'):
    return request(path, urllib.parse.urlencode(fields).encode(), method,
                   {'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': token()})


def api(payload, opener=client):
    return request('/api/extraction', json.dumps(payload).encode(), 'POST',
                   {'Content-Type': 'application/json'}, opener)


def upload(name, content):
    boundary = 'AttrfillReadinessBoundary'
    data = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\n'
            'Content-Type: text/csv\r\n\r\n').encode() + content + f'\r\n--{boundary}--\r\n'.encode()
    status, body, url = request('/batches', data, 'POST',
                               {'Content-Type': f'multipart/form-data; boundary={boundary}', 'X-CSRF-Token': token()})
    assert status == 200 and re.search(r'/batches/\d+$', url), (status, url)
    path = urllib.parse.urlparse(url).path
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        status, body, _ = request(path)
        assert status == 200
        if b'data-poll-done=' in body:
            return path, body.decode()
        time.sleep(0.5)
    raise AssertionError('Batch did not finish within 60 seconds')


def pages():
    paths = ['/', '/batches', '/reviews', '/metrics', '/up']
    for path in paths:
        status, body, _ = request(path)
        assert status == 200, (path, status)
        assert body
    status, body, _ = request('/')
    assets = re.findall(rb'(?:href|src)="(/assets/[^"?]+)', body)
    assert assets
    for asset in set(assets):
        assert request(asset.decode())[0] == 200, asset
    return {'pages': len(paths), 'assets': len(set(assets))}


def api_boundaries():
    for payload in [{'cards': 'bad'}, {'cards': ['bad']}, {'cards': [{}] * 501}]:
        assert api(payload)[0] == 422
    assert api({'cards': []})[0] == 200
    cards = [{'id': str(i), 'title': 'Смартфон Samsung Galaxy A15 8/256 ГБ черный'} for i in range(500)]
    status, body, _ = api({'cards': cards})
    assert status == 200, status
    found = json.loads(body)['cards']
    assert [x['id'] for x in found] == [x['id'] for x in cards]
    return {'accepted_batch': len(found), 'invalid_cases': 3}


def concurrent_api():
    payload = {'title': 'Смартфон Samsung Galaxy A15 8/256 ГБ черный'}
    def once(_):
        started = time.perf_counter()
        status, body, _ = api(payload, urllib.request.build_opener())
        assert status == 200, status
        return time.perf_counter() - started, json.loads(body)
    reference = once(None)[1]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        values = list(pool.map(once, range(32)))
    assert all(body == reference for _, body in values), 'Nondeterministic responses'
    times = sorted(seconds for seconds, _ in values)
    return {'requests': len(times), 'clients': 8, 'p50_seconds': statistics.median(times),
            'p95_seconds': times[int(0.95 * (len(times) - 1))]}


def card_flow():
    status, body, url = form('/cards', {'card[title]': 'Смартфон Samsung Galaxy A15 8/256 ГБ',
                                      'card[description]': 'Также есть версия на 128 ГБ'})
    assert status == 200 and re.search(r'/cards/\d+$', url), (status, url)
    return {'saved': True, 'url': urllib.parse.urlparse(url).path}


def batch_flow():
    path, page = upload('edge_cases.csv', Path('data/sample/edge_cases.csv').read_bytes())
    status, body, _ = request(path + '/download.json')
    assert status == 200
    cards = json.loads(body)
    assert len(cards) == 10, len(cards)
    match = re.search(r'data-\w+-url-value="/reviews/(\d+)"', page)
    if not match:
        match = re.search(r'/reviews/(\d+)', page)
    assert match, 'No inline review endpoint in finished batch'
    review = '/reviews/' + match[1]
    status, body, _ = form(review, {'decision': 'correct', 'value': 'Readiness correction'}, method='PATCH')
    assert status in (200, 302, 303), status
    status, body, _ = request(path + '/download.json')
    assert status == 200
    after = json.loads(body)
    changed = [(before['id'], name, value['value']) for before, final in zip(cards, after)
               for name, value in final['attributes'].items()
               if value['value'] != before['attributes'][name]['value']]
    assert changed, 'Review did not change downloaded result'
    return {'cards': len(cards), 'review_persisted_in_export': True, 'changed': changed}


def bad_upload():
    path, page = upload('broken.json', b'{"cards": [')
    assert 'JSON::ParserError' in page
    return {'failed_batch_page_renders': True, 'path': path}


def xss():
    payload = '<script>alert("readiness")</script>'
    status, body, url = form('/cards', {'card[title]': payload, 'card[category]': 'smartphone'})
    assert status == 200
    assert payload.encode() not in body, 'Unescaped script in result HTML'
    return {'raw_script_absent': True}


def csv_formula():
    output = io.StringIO()
    writer = csv.DictWriter(output, ['id', 'title', 'category', 'seller_attributes'])
    writer.writeheader()
    writer.writerow({'id': 'formula-probe', 'title': 'Смартфон', 'category': 'smartphone', 'seller_attributes': 'Бренд: =1+1'})
    path, _ = upload('formula.csv', output.getvalue().encode())
    status, body, _ = request(path + '/download.csv')
    assert status == 200
    rows = list(csv.DictReader(io.StringIO(body.decode())))
    formula = [r for r in rows if r['attribute'] == 'brand' and r['value'].startswith('=')]
    assert not formula, 'Unescaped spreadsheet formula in downloaded brand value (no spreadsheet was opened)'
    return {'formula_neutralized': True}


def accessory():
    status, body, _ = api({'title': 'Чехол для смартфона Samsung Galaxy S24 силиконовый'})
    assert status == 200
    result = json.loads(body)
    wrong = [value for value in result['attributes']
             if value['attribute'] in ['brand', 'model'] and value['value'] is not None]
    assert not wrong, 'Device attributes incorrectly extracted for an accessory: ' + json.dumps(wrong, ensure_ascii=False)
    return {'device_attributes_not_published': True}


def csrf_rejected():
    status, _, _ = request('/cards', urllib.parse.urlencode({'card[title]': 'CSRF probe'}).encode(), 'POST',
                            {'Content-Type': 'application/x-www-form-urlencoded'})
    assert status == 422, status
    return {'missing_token_rejected': True}


def group_review():
    content = io.StringIO()
    writer = csv.DictWriter(content, ['id', 'title', 'description', 'category'])
    writer.writeheader()
    for index in range(3):
        writer.writerow({'id': f'group-{index}', 'title': 'Смартфон Samsung Galaxy A15 8/256 ГБ синий',
                         'description': 'Цвет корпуса синий.', 'category': 'smartphone'})
    path, page = upload('duplicate-group.csv', content.getvalue().encode())
    before = json.loads(request(path + '/download.json')[1])
    preview = None
    for identifier in dict.fromkeys(re.findall(r'href="/review_groups/(\d+)"', page)):
        status, body, _ = request('/review_groups/' + identifier)
        if status == 200 and re.search(r'<h2[^>]*>\s*Color:', body.decode()):
            preview = body.decode()
            break
    assert preview, 'No group preview for color'
    assert len(re.findall(r'<li><a[^>]*href="/cards/\d+"', preview)) == 3
    signed = re.search(r'<input[^>]*name="token"[^>]*value="([^"]+)"', preview)
    assert signed, 'Missing signed group preview'
    status, body, _ = form('/review_groups', {'token': html.unescape(signed[1]),
                                            'decision': 'correct', 'value': 'черный'})
    assert status == 200, status
    undo = re.search(r'<input[^>]*name="token"[^>]*value="([^"]+)"', body.decode())
    assert undo, 'Missing undo receipt'
    after = json.loads(request(path + '/download.json')[1])
    assert all(card['attributes']['color']['value'] == 'черный' for card in after)
    assert all(card['attributes']['color']['status'] == 'accepted' for card in after)
    status, _, _ = form('/review_groups/undo', {'token': html.unescape(undo[1])})
    assert status == 200, status
    restored = json.loads(request(path + '/download.json')[1])
    assert restored == before, 'Undo did not restore exported predictions exactly'
    return {'cards': 3, 'one_group_decision': True, 'export_updated': True, 'undo_restores_export': True}



def duplicates(prefix, descriptions, title='Смартфон Samsung Galaxy A15 8/256 ГБ синий'):
    content = io.StringIO()
    writer = csv.DictWriter(content, ['id', 'title', 'description', 'category'])
    writer.writeheader()
    for index, description in enumerate(descriptions):
        writer.writerow({'id': f'{prefix}-{index}', 'title': title, 'description': description, 'category': 'smartphone'})
    return upload(f'{prefix}.csv', content.getvalue().encode())


def review_forms(page):
    """{value id: seen version} of the review forms on a page."""
    found = {}
    for match in re.finditer(r'action="/reviews/(\d+)"(.*?)</form>', page, re.S):
        seen = re.search(r'name="seen"[^>]*value="([^"]*)"', match[2]) or re.search(r'value="([^"]*)"[^>]*name="seen"', match[2])
        if seen:
            found[match[1]] = html.unescape(seen[1])
    return found


def color_preview(page):
    for identifier in dict.fromkeys(re.findall(r'/review_groups/(\d+)', page)):
        status, body, _ = request('/review_groups/' + identifier)
        if status == 200 and re.search(r'<h2[^>]*>\s*Color:', body.decode()):
            return identifier, body.decode()
    raise AssertionError('No group preview for color')


def signed(page):
    found = re.search(r'<input[^>]*name="token"[^>]*value="([^"]+)"', page)
    assert found, 'Missing signed token'
    return html.unescape(found[1])


def patch_review(identifier, fields, stream=True):
    headers = {'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': token()}
    if stream:
        headers['Accept'] = 'text/vnd.turbo-stream.html'
    return request('/reviews/' + identifier, urllib.parse.urlencode(fields).encode(), 'PATCH', headers)


def stale_decision():
    path, page = duplicates('stale', ['Цвет корпуса синий.'] * 2, 'Смартфон Xiaomi Redmi 13 8/256 ГБ синий')
    status, reviews, _ = request('/reviews')
    identifier, preview = color_preview(page)
    seen = review_forms(reviews.decode()).get(identifier) or review_forms(page).get(identifier)
    assert seen, 'Review form carries no version'
    status, body, _ = form('/review_groups', {'token': signed(preview), 'decision': 'correct', 'value': 'черный'})
    assert status == 200, status
    status, body, _ = patch_review(identifier, {'decision': 'reject', 'seen': seen})
    assert status == 409, status
    after = json.loads(request(path + '/download.json')[1])
    assert all(card['attributes']['color']['value'] == 'черный' for card in after), 'Stale decision overwrote the group'
    return {'stale_reject_refused': True, 'group_value_kept': True}


def group_scope_and_tokens():
    path, page = duplicates('scope', ['Цвет корпуса синий.', 'Цвет корпуса синий.', 'Комплект: чехол и зарядка.'],
                            'Смартфон Honor X8b 8/128 ГБ синий')
    identifier, preview = color_preview(page)
    listed = len(re.findall(r'<li><a[^>]*href="/cards/\d+"', preview))
    before = request(path + '/download.json')[1]
    status, _, url = form('/review_groups', {'token': signed(preview) + 'x', 'decision': 'approve'})
    assert status == 200 and url.endswith('/reviews'), (status, url)
    status, _, url = form('/review_groups/undo', {'token': signed(preview)})
    assert url.endswith('/reviews'), 'A preview token was accepted as an undo receipt'
    assert request(path + '/download.json')[1] == before, 'Rejected token changed the export'
    status, body, _ = form('/review_groups', {'token': signed(preview), 'decision': 'approve'})
    assert status == 200
    status, _, url = form('/review_groups', {'token': signed(preview), 'decision': 'approve'})
    assert url.endswith('/reviews'), 'The same preview was applied twice'
    return {'listed': listed, 'different_description_excluded': listed == 2, 'tampered_refused': True,
            'purpose_checked': True, 'replay_refused': True}


def export_matches_decisions():
    path, page = upload('decisions.csv', Path('data/sample/edge_cases.csv').read_bytes())
    forms = list(review_forms(page).items())
    assert len(forms) >= 2, 'Not enough values in review'

    def export():
        return {(card['id'], name): value for card in json.loads(request(path + '/download.json')[1])
                for name, value in card['attributes'].items()}

    def decide(decision, wanted):
        """Applies the decision to queued values until one with a value changes; an empty one must stay missing."""
        while forms:
            identifier, seen = forms.pop(0)
            before = export()
            assert patch_review(identifier, {'decision': decision, 'seen': seen})[0] == 200
            after = export()
            changed = {key: (before[key], after[key]) for key in after if after[key] != before[key]}
            if not changed:
                continue
            assert len(changed) == 1, changed
            old, new = next(iter(changed.values()))
            assert (old['status'], new['status']) == wanted, (old, new)
            assert all(value['status'] != 'accepted' or value['value'] is not None for value in after.values()), \
                'an accepted blank reached the export'
            return old, new
        raise AssertionError(f'no queued value with a value for {decision}')

    old, new = decide('approve', ('review', 'accepted'))
    assert new['value'] == old['value'] and new['value'] is not None
    old, new = decide('reject', ('review', 'missing'))
    assert new['value'] is None
    after = export()
    rows = list(csv.DictReader(io.StringIO(request(path + '/download.csv')[1].decode())))
    assert sum(1 for row in rows if row['status'] == 'review') == sum(1 for value in after.values() if value['status'] == 'review')
    return {'approved_kept_value': True, 'rejected_became_missing': True, 'confirmed_blank_stays_missing': True,
            'other_values_unchanged': True}


def json_and_noise():
    path, _ = upload('unlabelled.json', Path('data/sample/unlabelled.json').read_bytes())
    cards = json.loads(request(path + '/download.json')[1])
    assert cards, 'JSON upload produced no cards'
    path2, _ = upload('injection.jsonl', Path('data/stress/22_prompt_injection.jsonl').read_bytes())
    injected = json.loads(request(path2 + '/download.json')[1])
    started = time.perf_counter()
    status, body, _ = api({'title': 'Смартфон', 'description': 'Мусор ' * 5000})
    noise_seconds = time.perf_counter() - started
    assert status == 200 and noise_seconds < 15, (status, noise_seconds)
    status, body, _ = request('/api/extraction', b'{"title": ', 'POST', {'Content-Type': 'application/json'})
    assert status == 400 and json.loads(body)['error'], status
    status, _, url = form('/cards', {'card[title]': ' ', 'card[description]': ''})
    assert url.endswith('/cards/new'), url
    return {'json_cards': len(cards), 'jsonl_cards': len(injected), 'noise_seconds': round(noise_seconds, 2),
            'malformed_json': 400, 'empty_card_refused': True}

for name, fn in [('pages_and_assets', pages), ('single_card', card_flow), ('batch_review_export', batch_flow),
                 ('malformed_upload', bad_upload), ('api_boundaries_500', api_boundaries),
                 ('api_concurrency', concurrent_api), ('html_escape', xss), ('csrf_rejected', csrf_rejected),
                 ('accessory_device_attributes', accessory), ('csv_formula', csv_formula),
                 ('group_review_export_undo', group_review), ('stale_decision_conflict', stale_decision),
                 ('group_scope_tokens_replay', group_scope_and_tokens), ('export_matches_decisions', export_matches_decisions),
                 ('json_noise_empty', json_and_noise)]:
    check(name, fn)
print(json.dumps({'passed': sum(x['ok'] for x in results), 'total': len(results)}))

raise SystemExit(0 if all(x["ok"] for x in results) else 1)
