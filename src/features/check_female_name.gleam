import error.{type BotError}
import gleam/list
import gleam/option
import gleam/string
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{BanChatMemberParameters, Int}
import telega/update.{type Command, type Update}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let current_state = ctx.session.chat_settings.check_female_name
  let new_state = !current_state
  let result =
    storage.set_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      "check_female_name",
      sqlight.bool(new_state),
    )

  case result {
    Error(_) -> {
      let _ = reply(ctx, "Error: could not set property")
      Error(error.BotError("Error: could not set property"))
    }
    Ok(_) -> {
      let msg = case new_state {
        False ->
          "Success: bot will NOT kick joining accounts with ENG/RU female name"
        True ->
          "Success: bot will kick joining accounts with ENG/RU female name"
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
  case upd, ctx.session.chat_settings.check_female_name {
    update.ChatMemberUpdate(chat_member_updated:, chat_id:, ..), True -> {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          let is_female_name =
            ctx.session.resources.female_names
            |> list.contains(member.user.first_name |> string.lowercase())
          case is_female_name {
            False -> next(ctx, upd)
            True -> {
              let _ =
                api.ban_chat_member(
                  ctx.config.api_client,
                  parameters: BanChatMemberParameters(
                    chat_id: Int(chat_id),
                    user_id: member.user.id,
                    until_date: option.None,
                    revoke_messages: option.Some(True),
                  ),
                )
              next(ctx, upd)
            }
          }
        }
        _ -> next(ctx, upd)
      }

      next(ctx, upd)
    }
    _, _ -> next(ctx, upd)
  }
}
