import error
import gleam/dynamic/decode
import gleam/json

pub type ChatSettings {
  ChatSettings(
    kick_new_accounts: Int,
    strict_mode_nonmembers: Bool,
    no_links: Bool,
    check_chat_clones: Bool,
    check_female_name: Bool,
    check_banned_words: Bool,
    banned_words: List(String),
  )
}

pub fn default() {
  ChatSettings(
    kick_new_accounts: 0,
    no_links: False,
    strict_mode_nonmembers: False,
    check_chat_clones: False,
    check_female_name: False,
    check_banned_words: False,
    banned_words: [],
  )
}

pub fn chat_encoder(chat: ChatSettings) {
  json.object([
    #("kick_new_accounts", json.int(chat.kick_new_accounts)),
    #(
      "strict_mode_nonmembers",
      bool_as_int_encoder(chat.strict_mode_nonmembers),
    ),
    #("check_chat_clones", bool_as_int_encoder(chat.check_chat_clones)),
    #("check_female_name", bool_as_int_encoder(chat.check_chat_clones)),
    #("no_links", bool_as_int_encoder(chat.no_links)),
    #("check_banned_words", bool_as_int_encoder(chat.check_banned_words)),
    #("banned_words", json.array(chat.banned_words, json.string)),
  ])
}

fn bool_as_int_encoder(val: Bool) {
  json.int(case val {
    False -> 0
    True -> 1
  })
}

fn int_to_bool(int: Int) {
  case int {
    0 -> Ok(False)
    1 -> Ok(True)
    _ -> Error(error.GenericError("Cannot decode int as bool"))
  }
}

pub fn chat_decoder() {
  use kick_new_accounts <- decode.optional_field(
    "kick_new_accounts",
    0,
    decode.int,
  )

  //strict_mode_nonmembers
  use strict_mode_nonmembers <- decode.optional_field(
    "strict_mode_nonmembers",
    0,
    decode.int,
  )
  let assert Ok(strict_mode_nonmembers) = int_to_bool(strict_mode_nonmembers)

  //check_chat_clones
  use check_chat_clones <- decode.optional_field(
    "check_chat_clones",
    0,
    decode.int,
  )
  let assert Ok(check_chat_clones) = int_to_bool(check_chat_clones)

  //check_female_name
  use check_female_name <- decode.optional_field(
    "check_female_name",
    0,
    decode.int,
  )
  let assert Ok(check_female_name) = int_to_bool(check_female_name)

  //no_links
  use no_links <- decode.optional_field("no_links", 0, decode.int)
  let assert Ok(no_links) = int_to_bool(no_links)

  //check_banned_words
  use check_banned_words <- decode.optional_field(
    "check_banned_words",
    0,
    decode.int,
  )
  let assert Ok(check_banned_words) = int_to_bool(check_banned_words)

  //banned_words
  use banned_words <- decode.optional_field(
    "banned_words",
    [],
    decode.list(decode.string),
  )

  decode.success(ChatSettings(
    kick_new_accounts:,
    no_links:,
    strict_mode_nonmembers:,
    check_chat_clones:,
    check_female_name:,
    check_banned_words:,
    banned_words:,
  ))
}
