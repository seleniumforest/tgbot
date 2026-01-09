import telega/error

pub type BotError {
  BotError(String)
  TelegaError(error.TelegaError)
}
