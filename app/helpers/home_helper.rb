# The start page: ready examples for a demo in one click, and where the person left off.
module HomeHelper
  # Each one fills the form and sends it. The tablet always leaves a value for a person: "12 GB/512 GB" does not say
  # which number is the memory, so the jury sees the yellow value and the one-click fix.
  EXAMPLES = [
    { label: "Smartphone", title: "Смартфон Samsung Galaxy A55 8/256 ГБ, синий",
      description: "Экран 6,6 дюйма Super AMOLED, аккумулятор 5000 мАч. Также доступна версия на 128 ГБ.", seller: "Бренд: Samsung; Цвет: синий" },
    { label: "TV", title: "Телевизор LG 55UR78006LK 55\" 4K UHD Smart TV",
      description: "Яркая картинка 4K, HDR10, webOS. Подходит для настенного монтажа.", seller: "Цвет: чёрный" },
    # Not the made-up "Nordbook … Apple M2": one click sent it straight to a result with brand Apple and model M2, both
    # wrong and "sure". The demo should show right answers here and leave the doubt to the tablet.
    { label: "Laptop", title: "Ноутбук Lenovo IdeaPad Slim 3 15IAH8 15.6\" Intel Core i5-12450H 8/512 ГБ серый",
      description: "Стильный дизайн и высокая производительность. Официальная гарантия производителя.", seller: "" },
    { label: "Tablet, with a disputed field", title: "Планшет Samsung Galaxy Tab A9+ 12 ГБ/512 ГБ White",
      description: "Экран 11 дюймов. Аккумулятор 4500 mAh.", seller: "", disputed: true }
  ].freeze

  # The key the shortcut hint starts with, as the server can guess it; submit_shortcut corrects it from navigator.platform.
  def shortcut_modifier = request.user_agent.to_s.match?(/Macintosh|Mac OS X|iPhone|iPad/) ? "⌘" : "Ctrl"

  # The state of the last file in a few words, and what to do next: [text, tone of the dot].
  def last_batch_state(batch, waiting)
    if batch.pending? || batch.processing?
      [ "processing", "bg-sky-500" ]
    elsif batch.failed?
      [ "could not be read", "bg-brand-600" ]
    elsif waiting.positive?
      [ "#{num(waiting)} #{plural(waiting, "value waits", "values wait")} for review", "bg-amber-500" ]
    else
      [ "all checked", "bg-emerald-500" ]
    end
  end
end
