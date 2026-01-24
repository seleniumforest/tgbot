import error.{
  type BotError, DbConnectionError, EmptyDataError, InvalidValueError,
}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/list
import gleam/otp/actor
import models/chat_settings.{type ChatSettings} as ch
import sqlight

pub type StorageMessage {
  GetChat(reply_with: Subject(Result(ChatSettings, BotError)), id: Int)
  CreateChat(reply_with: Subject(Result(ChatSettings, BotError)), id: Int)
  SetChatProperty(
    reply_with: Subject(Result(Bool, BotError)),
    id: Int,
    prop: String,
    val: sqlight.Value,
    as_list: Bool,
  )
}

pub fn init() -> Subject(StorageMessage) {
  let connection = init_db()

  let assert Ok(actor) =
    actor.new(connection)
    |> actor.on_message(handle_message)
    |> actor.start

  actor.data
}

pub fn create_chat(actor: Subject(StorageMessage), id: Int) {
  process.call_forever(actor, fn(a) { CreateChat(a, id) })
}

pub fn get_chat(actor: Subject(StorageMessage), id: Int) {
  process.call_forever(actor, fn(a) { GetChat(a, id) })
}

pub fn set_chat_property(
  actor: Subject(StorageMessage),
  id: Int,
  prop: String,
  val: sqlight.Value,
) {
  process.call_forever(actor, fn(a) { SetChatProperty(a, id, prop, val, False) })
}

pub fn set_chat_property_list(
  actor: Subject(StorageMessage),
  id: Int,
  prop: String,
  val: sqlight.Value,
) {
  process.call_forever(actor, fn(a) { SetChatProperty(a, id, prop, val, True) })
}

fn string_decoder() {
  use id <- decode.field(0, decode.string)
  decode.success(id)
}

fn handle_message(
  connection: sqlight.Connection,
  message: StorageMessage,
) -> actor.Next(sqlight.Connection, StorageMessage) {
  case message {
    GetChat(id:, reply_with:) -> {
      let query =
        sqlight.query(
          "SELECT data FROM chats WHERE chat_id = ? LIMIT 1;",
          on: connection,
          with: [sqlight.int(id)],
          expecting: string_decoder(),
        )

      unwrap_query_to_settings(query, reply_with)
      actor.continue(connection)
    }

    SetChatProperty(reply_with:, id:, prop:, val:, as_list:) -> {
      let sql = case as_list {
        True -> "UPDATE chats 
            SET data = json_set(data, '$." <> prop <> "', json(?)) 
            WHERE chat_id = ?;"
        False -> "UPDATE chats 
            SET data = json_set(data, '$." <> prop <> "', ?) 
            WHERE chat_id = ?;"
      }

      let query =
        sqlight.query(
          sql,
          on: connection,
          with: [val, sqlight.int(id)],
          expecting: decode.dynamic,
        )

      case query {
        Error(e) -> process.send(reply_with, Error(DbConnectionError(e)))
        Ok(_) -> process.send(reply_with, Ok(True))
      }

      actor.continue(connection)
    }
    CreateChat(id:, reply_with:) -> {
      let default_chat =
        ch.default()
        |> ch.chat_encoder
        |> json.to_string
        |> sqlight.text

      let query =
        "INSERT INTO chats (chat_id, data) values (?, ?) RETURNING data;"
        |> sqlight.query(
          on: connection,
          with: [
            sqlight.int(id),
            default_chat,
          ],
          expecting: string_decoder(),
        )

      unwrap_query_to_settings(query, reply_with)
      actor.continue(connection)
    }
  }
}

fn unwrap_query_to_settings(
  query: Result(List(String), sqlight.Error),
  reply_with: Subject(Result(ChatSettings, BotError)),
) {
  case query {
    Error(e) -> process.send(reply_with, Error(DbConnectionError(e)))
    Ok(ls) -> {
      case list.first(ls) {
        Error(_) -> process.send(reply_with, Error(EmptyDataError))
        Ok(json) -> {
          case json.parse(from: json, using: ch.chat_decoder()) {
            Error(e) -> process.send(reply_with, Error(InvalidValueError(e)))
            Ok(obj) -> {
              process.send(reply_with, Ok(obj))
            }
          }
        }
      }
    }
  }
}

fn init_db() {
  let assert Ok(conn) = sqlight.open("file:data.sqlite3")

  let sql =
    "CREATE TABLE IF NOT EXISTS chats (
    chat_id INTEGER PRIMARY KEY,
    data JSON NULL);"
  let assert Ok(Nil) = sqlight.exec(sql, conn)
  conn
}
