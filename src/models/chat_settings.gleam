import gleam/dynamic/decode
import gleam/json

pub type ChatSettings {
  ChatSettings(
    //
    kick_new_accounts: Int,
    //
    no_links: Bool,
  )
}

pub fn default() {
  ChatSettings(kick_new_accounts: 0, no_links: False)
}

pub fn chat_encoder(chat: ChatSettings) {
  json.object([
    #("kick_new_accounts", json.int(chat.kick_new_accounts)),
    #("no_links", json.bool(chat.no_links)),
  ])
}

pub fn chat_decoder() {
  use kick_new_accounts <- decode.field("kick_new_accounts", decode.int)
  use no_links <- decode.field("no_links", decode.bool)
  decode.success(ChatSettings(kick_new_accounts, no_links))
}
