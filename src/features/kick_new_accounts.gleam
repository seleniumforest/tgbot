import error.{type BotError}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import helpers/log
import helpers/reply.{reply, reply_format}
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{BanChatMemberParameters, Int}
import telega/update.{type Command, type Update, ChatMemberUpdate}

pub fn command(
  ctx: Context(BotSession, BotError),
  cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let cmd_args =
    cmd.text
    |> string.split(" ")
    |> list.rest()
    |> result.unwrap([])
    |> list.filter(fn(x) { x |> string.is_empty |> bool.negate })

  let args_count = cmd_args |> list.length
  let first_arg =
    cmd_args
    |> list.first()
    |> result.unwrap("")
    |> int.parse()

  case first_arg {
    Error(_) -> {
      let current_state = ctx.session.chat_settings.kick_new_accounts
      let _ = case current_state, args_count {
        //when user has enabled kick_new_accounts feature, and provides no arguments
        cs, ac if cs > 0 && ac == 0 -> {
          let new_state = 0
          let result = set_state(ctx, current_state, new_state)
          result
        }
        _, _ -> {
          let _ = reply(ctx, "Error: please enter valid argument")

          Ok(ctx)
        }
      }
      Ok(ctx)
    }
    Ok(num) -> {
      let current_state = ctx.session.chat_settings.kick_new_accounts
      let new_state = num

      set_state(ctx, current_state, new_state)
    }
  }
}

fn set_state(
  ctx: Context(BotSession, BotError),
  current_state: Int,
  new_state: Int,
) {
  let result =
    storage.set_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      "kick_new_accounts",
      sqlight.int(new_state),
    )

  case result {
    Error(_) -> {
      let _ = reply(ctx, "Error: could not set property")
      Error(error.BotError("Could not set property"))
    }
    Ok(_) -> {
      let _ = case new_state {
        ns if ns > 0 ->
          reply_format(
            ctx,
            "Success: users with telegram id over {0} will be kicked",
            [new_state |> int.to_string()],
          )
        _ ->
          reply_format(
            ctx,
            "Success: users with telegram id over {0} will NOT be kicked",
            [current_state |> int.to_string()],
          )
      }

      Ok(ctx)
    }
  }
}

pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> a,
) -> a {
  let ids_to_delete = ctx.session.chat_settings.kick_new_accounts

  case upd, ids_to_delete {
    ChatMemberUpdate(chat_id:, chat_member_updated:, ..), itd if itd > 0 -> {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          case member.user.id > ids_to_delete && !member.user.is_bot {
            False -> next(ctx, upd)
            True -> {
              log.print("Ban user: {0} {1} id: {2} reason: fresh account", [
                member.user.first_name,
                member.user.last_name |> option.unwrap(""),
                int.to_string(member.user.id),
              ])

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
    }

    _, _ -> next(ctx, upd)
  }
}
