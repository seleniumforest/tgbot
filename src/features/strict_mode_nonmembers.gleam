import error.{type BotError}
import gleam/bool
import gleam/list
import gleam/option
import gleam/regexp
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
  let result =
    storage.set_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      "strict_mode_nonmembers",
      sqlight.bool(new_state),
    )

  case result {
    Error(_) -> {
      let _ = reply(ctx, "Error: could not set property")
      Error(error.BotError("Error: could not set property"))
    }
    Ok(_) -> {
      let msg = case new_state {
        False -> "Success: strict mode for non-members disabled"
        True ->
          "Success: strict mode (no media, links, reactions) for non-members enabled"
      }
      let _ = reply(ctx, msg)

      Ok(ctx)
    }
  }
}

pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> a,
) -> a {
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

      let chat_member =
        api.get_chat_member(
          ctx.config.api_client,
          GetChatMemberParameters(chat_id: Int(chat_id), user_id: from_id),
        )
      case chat_member {
        Error(_) -> next(ctx, upd)
        Ok(mem) -> {
          case mem {
            types.ChatMemberLeftChatMember(_) -> {
              use <- bool.lazy_guard(!has_some_shit(message), fn() {
                next(ctx, upd)
              })

              log.print("Delete message {0} reason: strict mode", [
                message.text |> option.unwrap(""),
              ])

              let _ =
                api.delete_message(
                  ctx.config.api_client,
                  types.DeleteMessageParameters(
                    chat_id: Int(chat_id),
                    message_id: message.message_id,
                  ),
                )
              next(ctx, upd)
            }
            _ -> next(ctx, upd)
          }
        }
      }
      next(ctx, upd)
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
