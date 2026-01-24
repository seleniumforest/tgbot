import error.{type BotError}
import gleam/bool
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import helpers/log
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{BanChatMemberParameters, DeleteMessageParameters, Int}
import telega/update.{type Command, type Update}

// Toggle check_banned_words on/off
pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let current_state = ctx.session.chat_settings.check_banned_words
  let new_state = !current_state

  storage.set_chat_property_list(
    ctx.session.db,
    ctx.update.chat_id,
    "check_banned_words",
    sqlight.bool(new_state),
  )
  |> result.try(fn(_) {
    reply(ctx, case new_state {
      False -> "Success: bot will NOT ban users for banned words"
      True -> "Success: bot will ban users for banned words"
    })
  })
  |> result.try(fn(_) { Ok(ctx) })
}

// Add a banned word
pub fn add_word_command(
  ctx: Context(BotSession, BotError),
  cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let words_to_add =
    cmd.text
    |> string.lowercase
    |> string.split(" ")
    |> list.rest()
    |> result.unwrap([])
    |> list.filter(fn(x) { !string.is_empty(x) })

  case list.is_empty(words_to_add) {
    True -> reply(ctx, "Usage: /addBanWord <word1> [word2] [word3] ...")
    False -> {
      let current_words = ctx.session.chat_settings.banned_words
      let new_words =
        list.append(current_words, words_to_add)
        |> list.unique

      let json_value =
        new_words
        |> json.array(of: json.string)
        |> json.to_string
        |> sqlight.text

      storage.set_chat_property_list(
        ctx.session.db,
        ctx.update.chat_id,
        "banned_words",
        json_value,
      )
      |> result.try(fn(_) {
        reply(
          ctx,
          log.format("Added words: {0}\nTotal:  {1}", [
            string.join(words_to_add, ", "),
            int.to_string(list.length(new_words)),
          ]),
        )
      })
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

// Remove a banned word
pub fn remove_word_command(
  ctx: Context(BotSession, BotError),
  cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let words_to_remove =
    cmd.text
    |> string.split(" ")
    |> list.rest()
    |> result.unwrap([])
    |> list.filter(fn(x) { !string.is_empty(x) })
    |> list.map(fn(x) { string.lowercase(x) })

  case list.is_empty(words_to_remove) {
    True -> reply(ctx, "Usage: /removeBanWord <word1> [word2] [word3] ...")
    False -> {
      let current_words = ctx.session.chat_settings.banned_words
      let new_words =
        current_words
        |> list.filter(fn(w) { !list.contains(words_to_remove, w) })

      let json_value =
        new_words
        |> json.array(of: json.string)
        |> json.to_string
        |> sqlight.text

      storage.set_chat_property_list(
        ctx.session.db,
        ctx.update.chat_id,
        "banned_words",
        json_value,
      )
      |> result.try(fn(_) {
        reply(
          ctx,
          log.format("Removed words: {0}\nRemaining: {1}", [
            string.join(words_to_remove, ", "),
            int.to_string(list.length(new_words)),
          ]),
        )
      })
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

// Checker for messages
pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> Nil,
) -> Nil {
  let banned_words = ctx.session.chat_settings.banned_words
  let needs_check =
    ctx.session.chat_settings.check_banned_words && !list.is_empty(banned_words)

  use <- bool.lazy_guard(!needs_check, fn() { next(ctx, upd) })

  case upd {
    update.TextUpdate(from_id:, chat_id:, message:, ..)
    | update.AudioUpdate(from_id:, chat_id:, message:, ..)
    | update.EditedMessageUpdate(from_id:, chat_id:, message:, ..)
    | update.MessageUpdate(from_id:, chat_id:, message:, ..)
    | update.PhotoUpdate(from_id:, chat_id:, message:, ..)
    | update.VideoUpdate(from_id:, chat_id:, message:, ..)
    | update.VoiceUpdate(from_id:, chat_id:, message:, ..) -> {
      let text = message.text |> option.unwrap("")
      let caption = message.caption |> option.unwrap("")

      let contains_banned =
        string.lowercase(text <> " " <> caption)
        |> string.split(" ")
        |> list.filter(fn(x) { !string.is_empty(x) })
        |> set.from_list
        |> set.is_disjoint(set.from_list(banned_words))
        |> bool.negate

      use <- bool.lazy_guard(!contains_banned, fn() { next(ctx, upd) })

      log.printf("Ban user id: {0} reason: banned word in message", [
        from_id |> int.to_string,
      ])

      // Delete the message first
      let _ =
        api.delete_message(
          ctx.config.api_client,
          DeleteMessageParameters(
            chat_id: Int(chat_id),
            message_id: message.message_id,
          ),
        )

      case message.sender_chat {
        option.None ->
          api.ban_chat_member(
            ctx.config.api_client,
            parameters: BanChatMemberParameters(
              chat_id: Int(chat_id),
              user_id: from_id,
              until_date: option.None,
              revoke_messages: option.Some(True),
            ),
          )
        option.Some(sc) ->
          api.ban_chat_sender_chat(
            ctx.config.api_client,
            types.BanChatSenderChatParameters(
              chat_id: Int(chat_id),
              sender_chat_id: sc.id,
            ),
          )
      }
      |> result.map(fn(_) { Nil })
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}
