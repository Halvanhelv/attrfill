# Libraries and licences

All components are free software; there are no copyleft licences (GPL etc.) in the solution.

## Runtime and external services

| Component | Version | Licence | Where it is used |
|---|---|---|---|
| Ruby | 3.4.2 | Ruby / BSD-2-Clause | language of the solution |
| SQLite | 3 | Public domain | demo application database |
| Turbo, Stimulus (JS, via importmap) | see gems | MIT | interface |
| Tailwind CSS | see the tailwindcss-ruby gem | MIT | interface styles |
| ONNX Runtime (inside the onnxruntime gem) | 1.x | MIT | running the neural tagger |
| Model `cointegrated/rubert-tiny2` | — | MIT | base of the neural tagger (optional stage) |
| LLM (Claude / OpenAI-compatible, customer's key) | — | provider's terms, called via API | third stage, optional |

## Python (only for training the neural tagger and open-data converters; not needed to run the solution)

| Package | Licence | File |
|---|---|---|
| torch | BSD-3-Clause | `script/ner/requirements.txt` |
| transformers | Apache-2.0 | `script/ner/requirements.txt` |
| onnx | Apache-2.0 | `script/ner/requirements.txt` |
| onnxruntime | MIT | `script/ner/requirements.txt` |
| pandas | BSD-3-Clause | `script/convert/ozon.py` |
| pyarrow | Apache-2.0 | `script/convert/ozon.py` |

## Ruby gems (full list from `Gemfile.lock`)

Generated with:

```bash
bundle exec ruby -e 'Bundler.load.specs.sort_by(&:name).each { |s| puts "| #{s.name} | #{s.version} | #{s.licenses.join(" / ")} |" }'
```

"Ruby" is the Ruby language licence (dual, with BSD-2-Clause). `rdoc` is dual-licensed Ruby / GPL-2.0, and Ruby
applies; `rdoc`, `rubocop*`, `debug`, `web-console` are needed only in development.

| Gem | Version | Licence |
|---|---|---|
| action_text-trix | 2.1.19 | MIT |
| actioncable | 8.1.4 | MIT |
| actionmailbox | 8.1.4 | MIT |
| actionmailer | 8.1.4 | MIT |
| actionpack | 8.1.4 | MIT |
| actiontext | 8.1.4 | MIT |
| actionview | 8.1.4 | MIT |
| activejob | 8.1.4 | MIT |
| activemodel | 8.1.4 | MIT |
| activerecord | 8.1.4 | MIT |
| activestorage | 8.1.4 | MIT |
| activesupport | 8.1.4 | MIT |
| ast | 2.4.3 | MIT |
| base64 | 0.3.0 | Ruby / BSD-2-Clause |
| bigdecimal | 4.1.3 | Ruby / BSD-2-Clause |
| bindex | 0.8.1 | MIT |
| bootsnap | 1.26.0 | MIT |
| builder | 3.3.0 | MIT |
| bundler | 4.0.20 | MIT |
| concurrent-ruby | 1.3.8 | MIT |
| connection_pool | 3.0.2 | MIT |
| crass | 1.0.7 | MIT |
| csv | 3.3.6 | Ruby / BSD-2-Clause |
| date | 3.6.0 | Ruby / BSD-2-Clause |
| debug | 1.11.1 | Ruby / BSD-2-Clause |
| drb | 2.2.3 | Ruby / BSD-2-Clause |
| erb | 6.0.7 | Ruby / BSD-2-Clause |
| erubi | 1.13.1 | MIT |
| et-orbi | 1.4.2 | MIT |
| faraday | 2.14.4 | MIT |
| faraday-multipart | 1.2.0 | MIT |
| faraday-net_http | 3.4.4 | MIT |
| faraday-retry | 2.4.0 | MIT |
| ffi | 1.17.4 | BSD-3-Clause |
| fugit | 1.14.0 | MIT |
| globalid | 1.4.0 | MIT |
| i18n | 1.15.2 | MIT |
| importmap-rails | 2.2.3 | MIT |
| io-console | 0.9.4 | Ruby / BSD-2-Clause |
| irb | 1.18.0 | Ruby / BSD-2-Clause |
| json | 3.1.0 | Ruby |
| language_server-protocol | 3.17.0.6 | MIT |
| lint_roller | 1.1.0 | MIT |
| logger | 1.7.0 | Ruby / BSD-2-Clause |
| loofah | 2.25.2 | MIT |
| mail | 2.9.1 | MIT |
| marcel | 1.2.1 | MIT / Apache-2.0 |
| mini_mime | 1.1.5 | MIT |
| minitest | 6.0.6 | MIT |
| msgpack | 1.8.5 | Apache-2.0 |
| multipart-post | 2.4.1 | MIT |
| net-http | 0.10.0 | Ruby / BSD-2-Clause |
| net-imap | 0.6.8 | Ruby / BSD-2-Clause |
| net-pop | 0.1.2 | Ruby / BSD-2-Clause |
| net-protocol | 0.4.0 | Ruby / BSD-2-Clause |
| net-smtp | 0.5.2 | Ruby / BSD-2-Clause |
| nio4r | 2.7.5 | MIT / BSD-2-Clause |
| nokogiri | 1.19.4 | MIT |
| onnxruntime | 0.11.8 | MIT |
| parallel | 2.3.0 | MIT |
| parser | 3.3.12.0 | MIT |
| pp | 0.6.4 | Ruby / BSD-2-Clause |
| prettyprint | 0.2.1 | Ruby / BSD-2-Clause |
| prism | 1.9.0 | MIT |
| propshaft | 1.3.2 | MIT |
| puma | 8.0.2 | BSD-3-Clause |
| raabro | 1.5.0 | MIT |
| racc | 1.8.1 | Ruby / BSD-2-Clause |
| rack | 3.2.7 | MIT |
| rack-session | 2.1.2 | MIT |
| rack-test | 2.2.0 | MIT |
| rackup | 2.3.1 | MIT |
| rails | 8.1.4 | MIT |
| rails-dom-testing | 2.3.0 | MIT |
| rails-html-sanitizer | 1.7.1 | MIT |
| railties | 8.1.4 | MIT |
| rainbow | 3.1.1 | MIT |
| rake | 13.4.2 | MIT |
| rbs | 4.2.0 | BSD-2-Clause / Ruby |
| rdoc | 8.1.0 | Ruby / GPL-2.0-only |
| regexp_parser | 2.13.1 | MIT |
| reline | 0.7.0 | Ruby |
| rubocop | 1.92.0 | MIT |
| rubocop-ast | 1.50.0 | MIT |
| rubocop-performance | 1.27.0 | MIT |
| rubocop-rails | 2.38.0 | MIT |
| rubocop-rails-omakase | 1.1.0 | MIT |
| ruby-progressbar | 1.13.0 | MIT |
| ruby_llm | 2.1.1 | MIT |
| schematist | 1.1.0 | MIT |
| securerandom | 0.4.1 | Ruby / BSD-2-Clause |
| solid_cache | 1.0.10 | MIT |
| solid_queue | 1.7.0 | MIT |
| sqlite3 | 2.9.6 | BSD-3-Clause |
| stimulus-rails | 1.3.4 | MIT |
| tailwindcss-rails | 4.6.0 | MIT |
| tailwindcss-ruby | 4.3.3 | MIT |
| thor | 1.5.0 | MIT |
| timeout | 0.6.1 | Ruby / BSD-2-Clause |
| tokenizers | 0.7.0 | Apache-2.0 |
| tsort | 0.2.0 | Ruby / BSD-2-Clause |
| turbo-rails | 2.0.23 | MIT |
| tzinfo | 2.0.6 | MIT |
| unicode-display_width | 3.3.0 | MIT |
| unicode-emoji | 4.3.0 | MIT |
| uri | 1.1.2 | Ruby / BSD-2-Clause |
| useragent | 0.16.11 | MIT |
| web-console | 4.3.0 | MIT |
| websocket-driver | 0.8.2 | Apache-2.0 |
| websocket-extensions | 0.1.5 | Apache-2.0 |
| zeitwerk | 2.8.3 | MIT |
