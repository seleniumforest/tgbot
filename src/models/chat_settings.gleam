import error
import gleam/dynamic/decode
import gleam/json

pub type ChatSettings {
  ChatSettings(
    kick_new_accounts: Int,
    remove_comments_nonmembers: Bool,
    no_links: Bool,
  )
}

pub fn default() {
  ChatSettings(
    kick_new_accounts: 0,
    no_links: False,
    remove_comments_nonmembers: False,
  )
}

pub fn chat_encoder(chat: ChatSettings) {
  json.object([
    #("kick_new_accounts", json.int(chat.kick_new_accounts)),
    #(
      "remove_comments_nonmembers",
      bool_as_int_encoder(chat.remove_comments_nonmembers),
    ),
    #("no_links", bool_as_int_encoder(chat.no_links)),
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
    _ -> Error(error.BotError("Cannot decode int as bool"))
  }
}

pub fn chat_decoder() {
  use kick_new_accounts <- decode.optional_field(
    "kick_new_accounts",
    0,
    decode.int,
  )
  use remove_comments_nonmembers <- decode.optional_field(
    "remove_comments_nonmembers",
    0,
    decode.int,
  )
  let assert Ok(remove_comments_nonmembers) =
    int_to_bool(remove_comments_nonmembers)

  use no_links <- decode.optional_field("no_links", 0, decode.int)
  let assert Ok(no_links) = int_to_bool(no_links)

  decode.success(ChatSettings(
    kick_new_accounts:,
    no_links:,
    remove_comments_nonmembers:,
  ))
}
