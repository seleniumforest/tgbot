import error.{type BotError}
import gleam/bool
import gleam/list
import gleam/option
import gleam/regexp
import gleam/result
import gleam/string
import helpers/log
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{GetChatMemberParameters, Int}
import telega/update.{type Command, type Update}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let current_state = ctx.session.chat_settings.strict_mode_nonmembers
  let new_state = !current_state

  storage.set_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    "strict_mode_nonmembers",
    sqlight.bool(new_state),
  )
  |> result.try(fn(_) {
    reply(ctx, case new_state {
      False -> "Success: strict mode for non-members disabled"
      True ->
        "Success: strict mode (no media, links, reactions, female name) for non-members enabled"
    })
  })
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(
    !ctx.session.chat_settings.strict_mode_nonmembers,
    fn() { next(ctx, upd) },
  )

  case upd {
    update.TextUpdate(from_id:, chat_id:, message:, ..)
    | update.AudioUpdate(from_id:, chat_id:, message:, ..)
    | update.EditedMessageUpdate(from_id:, chat_id:, message:, ..)
    | update.MessageUpdate(from_id:, chat_id:, message:, ..)
    | update.PhotoUpdate(from_id:, chat_id:, message:, ..)
    | update.VideoUpdate(from_id:, chat_id:, message:, ..)
    | update.VoiceUpdate(from_id:, chat_id:, message:, ..) -> {
      let is_forward =
        message.reply_to_message
        |> option.map(fn(rtm) { rtm.is_automatic_forward })
        |> option.flatten
        |> option.unwrap(False)

      use <- bool.lazy_guard(!is_forward, fn() { next(ctx, upd) })

      api.get_chat_member(
        ctx.config.api_client,
        GetChatMemberParameters(chat_id: Int(chat_id), user_id: from_id),
      )
      |> result.try(fn(mem) {
        case mem {
          types.ChatMemberLeftChatMember(member) -> {
            use <- bool.lazy_guard(
              member.user.is_premium |> option.unwrap(False),
              fn() { Ok(next(ctx, upd)) },
            )

            let is_female_name =
              ctx.session.resources.female_names
              |> list.contains(member.user.first_name |> string.lowercase())

            let needs_delete = is_female_name || has_some_shit(message)
            use <- bool.lazy_guard(!needs_delete, fn() { Ok(next(ctx, upd)) })

            api.delete_message(
              ctx.config.api_client,
              types.DeleteMessageParameters(
                chat_id: Int(chat_id),
                message_id: message.message_id,
              ),
            )
            |> result.map(fn(_) { Nil })
          }
          _ -> Ok(next(ctx, upd))
        }
      })
      |> result.map_error(fn(err) {
        log.print_err(err |> string.inspect)
        err
      })
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}

fn has_some_shit(msg: types.Message) -> Bool {
  let is_audio = msg.audio |> option.is_some
  let is_photo = msg.photo |> option.is_some
  let is_video = msg.video |> option.is_some
  let is_video_note = msg.video_note |> option.is_some
  let is_game = msg.game |> option.is_some
  let is_document = msg.document |> option.is_some
  let is_sticker = msg.sticker |> option.is_some
  let is_caption_entities =
    msg.caption_entities |> option.unwrap([]) |> list.is_empty |> bool.negate

  let has_entities =
    msg.entities |> option.unwrap([]) |> list.is_empty |> bool.negate

  let contains_link = case regexp.from_string("https?://\\S+") {
    Ok(url_regex) -> {
      regexp.scan(with: url_regex, content: msg.text |> option.unwrap(""))
      |> list.is_empty
      |> bool.negate
    }
    Error(_) -> False
  }

  is_audio
  || is_photo
  || contains_link
  || has_entities
  || is_video
  || is_video_note
  || is_game
  || is_document
  || is_sticker
  || is_caption_entities
}
