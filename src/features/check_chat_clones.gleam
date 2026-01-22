import error.{type BotError}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{Int}
import telega/update.{type Command, type Update}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let current_state = ctx.session.chat_settings.check_chat_clones
  let new_state = !current_state

  storage.set_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    "check_chat_clones",
    sqlight.bool(new_state),
  )
  |> result.try(fn(_) {
    reply(ctx, case new_state {
      False ->
        "Success: bot will NOT try to find accounts whose name is similar to chat title"
      True ->
        "Success: bot will try to find accounts whose name is similar to chat title"
    })
  })
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(!ctx.session.chat_settings.check_chat_clones, fn() {
    next(ctx, upd)
  })

  case upd {
    update.AudioUpdate(message:, ..)
    | update.BusinessMessageUpdate(message:, ..)
    | update.CommandUpdate(message:, ..)
    | update.EditedBusinessMessageUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.MessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      message.from
      |> option.then(fn(from) {
        let last_first =
          from.last_name |> option.unwrap("") <> " " <> from.first_name
        let first_last =
          from.first_name <> " " <> from.last_name |> option.unwrap("")

        let chat_title = message.chat.title |> option.unwrap("")
        let cmp1 = smart_compare(last_first, chat_title)
        let cmp2 = smart_compare(first_last, chat_title)

        case cmp1, cmp2 {
          False, False -> Some(next(ctx, upd))
          _, _ -> {
            api.delete_message(
              ctx.config.api_client,
              types.DeleteMessageParameters(
                chat_id: Int(message.chat.id),
                message_id: message.message_id,
              ),
            )
            |> result.try(fn(_) { Ok(Some(Nil)) })
            |> result.lazy_unwrap(fn() { Some(next(ctx, upd)) })
          }
        }
      })
      |> option.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}

pub fn smart_compare(str1: String, str2: String) -> Bool {
  normalize(str1) == normalize(str2)
}

fn normalize(str: String) -> String {
  str
  |> string.lowercase()
  |> string.to_graphemes()
  |> list.chunk(by: fn(x) { x })
  |> list.map(fn(group) {
    case list.first(group) {
      Ok(char) -> char
      Error(_) -> ""
    }
  })
  |> list.map(fn(x) {
    dict.get(similarity_map(), x)
    |> result.unwrap(x)
  })
  |> string.join("")
  |> string.trim()
}

fn similarity_map() -> Dict(String, String) {
  dict.from_list([
    // Group 4
    #("а", "4"),
    #("a", "4"),
    #("ч", "4"),
    // // Group 8
    #("в", "8"),
    #("б", "8"),
    #("b", "8"),
    #("6", "8"),
    // Group 3
    #("е", "3"),
    #("e", "3"),
    #("з", "3"),
    #("э", "3"),
    #("€", "3"),
    // Group 1
    #("i", "1"),
    #("l", "1"),
    #("|", "1"),
    #("!", "1"),
    // Group 0
    #("o", "0"),
    #("о", "0"),
    // Group 5
    #("с", "5"),
    #("c", "5"),
    #("s", "5"),
    #("$", "5"),
    // Group 7
    #("т", "7"),
    #("t", "7"),
    // Group Y
    #("y", "y"),
    #("v", "y"),
    // Group X
    #("ж", "x"),
    #("%", "x"),
    // Group W
    #("ш", "w"),
    #("щ", "w"),
    #("w", "w"),
    // Group R
    #("я", "r"),
    #("r", "r"),
    //cyrillic-latin
    #("к", "k"),
    #("у", "y"),
    #("ё", "e"),
    #("е", "e"),
    #("B", "b"),
    #("х", "x"),
    #("н", "h"),
    #("р", "p"),
    #("т", "t"),
    #("M", "m"),
  ])
}
