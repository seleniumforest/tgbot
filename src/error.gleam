import gleam/json
import sqlight
import telega/error

pub type BotError {
  GenericError(String)
  TelegaLibError(error.TelegaError)

  //storage errors
  InvalidValueError(json.DecodeError)
  DbConnectionError(sqlight.Error)
  EmptyDataError
}
