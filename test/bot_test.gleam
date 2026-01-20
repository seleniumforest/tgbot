import features/check_chat_clones.{smart_compare}
import gleam/list
import gleeunit
import gleeunit/should
import helpers/log

pub fn main() {
  gleeunit.main()
}

pub fn smart_compare_test() {
  [
    #("apple", "banana"),
    #("Грязин Лаундж Зон", "Gryazin"),
    #("Gagarin Crypto Chat", "Gagarin Crypto"),
    #("Gagarin Crypto Chat", "alpaca"),
    #("Gagarin Crypto Chat", "Chat Gagarin Crypt0"),
  ]
  |> list.each(fn(el) {
    let result = smart_compare(el.0, el.1)
    case result {
      False -> should.be_false(result)
      True -> {
        log.print("FAIL: Strings `{0}` and `{1} should be not equal`", [
          el.0,
          el.1,
        ])
        should.be_false(result)
      }
    }
  })

  [
    #("альпака чат", "альпака чат"),
    #("boss", "8o55"),
    #("HELLO", "helloo"),
    #(" hello ", "hello"),
    #("Грязин Лаундж Зон", "Грязин Лаундж З0н"),
    #("Грязин Лаундж Зон", " Гря3ин  Лаундж  Зон"),
    #("Gagarin Crypto Chat", "Gagarin Crypto Chat"),
    #("Gagarin Crypto Chat", "Gag4r1n Crypt0 Ch4t"),
    #("Gagarin Crypto Chat", " Gag4r1n Crypt0 Ch4t "),
  ]
  |> list.each(fn(el) {
    let result = smart_compare(el.0, el.1)
    case result {
      False -> {
        log.print("FAIL: Strings `{0}` and `{1} should be equal`", [
          el.0,
          el.1,
        ])
        should.be_true(result)
      }
      True -> {
        should.be_true(result)
      }
    }
  })
}
