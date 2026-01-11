import error.{type BotError}
import gleam/option
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{GetChatMemberParameters, Int}
import telega/reply
import telega/update.{type Command, type Update}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let current_state = ctx.session.chat_settings.remove_comments_nonmembers
  let new_state = !current_state
  let result =
    storage.set_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      "remove_comments_nonmembers",
      sqlight.bool(new_state),
    )

  case result {
    Error(_) -> {
      let _ = reply.with_text(ctx, "Error: could not set property")
      Error(error.BotError("Error: could not set property"))
    }
    Ok(_) -> {
      let msg = case new_state {
        False ->
          "Success: bot will NOT delete comments from non members anymore"
        True -> "Success: bot will delete comments from non members"
      }
      let _ = reply.with_text(ctx, msg)

      Ok(ctx)
    }
  }
}

pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> a,
) -> a {
  case upd, ctx.session.chat_settings.remove_comments_nonmembers {
    update.TextUpdate(_text, _raw, from_id:, chat_id:, message:), True -> {
      let is_forward =
        message.reply_to_message
        |> option.map(fn(rtm) { rtm.is_automatic_forward })
        |> option.flatten
        |> option.unwrap(False)

      case is_forward {
        False -> next(ctx, upd)
        True -> {
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
                  echo "Delete message: "
                    <> message.text |> option.unwrap("")
                    <> " reason: user not a chat member"

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
      }
    }
    _, _ -> next(ctx, upd)
  }
}
