import error.{type BotError}
import gleam/bool
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import helpers/log
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import models/chat_settings
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

  storage.set_chat_property(
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
    |> string.split(" ")
    |> list.rest()
    |> result.unwrap([])
    |> list.filter(fn(x) { !string.is_empty(x) })
    |> list.map(fn(x) { string.lowercase(x) })

  case list.is_empty(words_to_add) {
    True -> reply(ctx, "Usage: /addBanWord <word1> [word2] [word3] ...")
    False -> {
      let current_words = ctx.session.chat_settings.banned_words
      let new_words =
        list.append(current_words, words_to_add)
        |> list.unique

      let new_settings =
        chat_settings.ChatSettings(
          ..ctx.session.chat_settings,
          banned_words: new_words,
        )
      let json_value =
        new_settings
        |> chat_settings.chat_encoder
        |> json.to_string
        |> sqlight.text

      storage.set_chat_data(ctx.session.db, ctx.update.chat_id, json_value)
      |> result.try(fn(_) {
        reply(
          ctx,
          "Added words: " <> string.join(words_to_add, ", ") <> "\nTotal: " <> int.to_string(
            list.length(new_words),
          ),
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

      let new_settings =
        chat_settings.ChatSettings(
          ..ctx.session.chat_settings,
          banned_words: new_words,
        )
      let json_value =
        new_settings
        |> chat_settings.chat_encoder
        |> json.to_string
        |> sqlight.text

      storage.set_chat_data(ctx.session.db, ctx.update.chat_id, json_value)
      |> result.try(fn(_) {
        reply(
          ctx,
          "Removed words: " <> string.join(words_to_remove, ", ") <> "\nRemaining: " <> int.to_string(
            list.length(new_words),
          ),
        )
      })
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

// List all banned words
pub fn list_words_command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let words = ctx.session.chat_settings.banned_words

  case list.is_empty(words) {
    True -> reply(ctx, "No banned words configured.\nUse /addBanWord <word> to add.")
    False -> {
      let words_list = string.join(words, ", ")
      reply(
        ctx,
        "Banned words (" <> int.to_string(list.length(words)) <> "):\n" <> words_list,
      )
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
  use <- bool.lazy_guard(!ctx.session.chat_settings.check_banned_words, fn() {
    next(ctx, upd)
  })

  let banned_words = ctx.session.chat_settings.banned_words

  use <- bool.lazy_guard(list.is_empty(banned_words), fn() { next(ctx, upd) })

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
      let full_text = string.lowercase(text <> " " <> caption)

      let contains_banned =
        banned_words
        |> list.any(fn(word) { string.contains(full_text, word) })

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

      // Then ban the user
      api.ban_chat_member(
        ctx.config.api_client,
        parameters: BanChatMemberParameters(
          chat_id: Int(chat_id),
          user_id: from_id,
          until_date: option.None,
          revoke_messages: option.Some(True),
        ),
      )
      |> result.map(fn(_) { Nil })
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}
