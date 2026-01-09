import gleam/erlang/process
import models/chat_settings.{type ChatSettings}
import storage

pub type BotSession {
  BotSession(
    chat_settings: ChatSettings,
    db: process.Subject(storage.StorageMessage),
  )
}

pub fn default(db: process.Subject(storage.StorageMessage)) {
  BotSession(chat_settings: chat_settings.default(), db:)
}
