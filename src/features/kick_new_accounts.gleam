import error.{type BotError}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import helpers/log
import helpers/reply.{reply, replyf}
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
      case current_state, args_count {
        //when user has enabled kick_new_accounts feature, and provides no arguments
        cs, ac if cs > 0 && ac == 0 -> {
          let new_state = 0
          set_state(ctx, current_state, new_state)
        }
        _, _ -> reply(ctx, "Error: please enter valid argument")
      }
    }
    Ok(num) -> {
      let current_state = ctx.session.chat_settings.kick_new_accounts
      let new_state = num

      set_state(ctx, current_state, new_state)
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

fn set_state(
  ctx: Context(BotSession, BotError),
  current_state: Int,
  new_state: Int,
) {
  storage.set_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    "kick_new_accounts",
    sqlight.int(new_state),
  )
  |> result.try(fn(_) {
    case new_state {
      ns if ns > 0 ->
        replyf(
          ctx,
          "Success: joining users with telegram id over {0} will be kicked",
          [new_state |> int.to_string()],
        )
      _ ->
        replyf(
          ctx,
          "Success: joining users with telegram id over {0} will NOT be kicked",
          [current_state |> int.to_string()],
        )
    }
  })
}

pub fn checker(
  ctx: Context(BotSession, BotError),
  upd: Update,
  next: fn(Context(BotSession, BotError), Update) -> Nil,
) -> Nil {
  let ids_to_delete = ctx.session.chat_settings.kick_new_accounts

  case upd, ids_to_delete {
    ChatMemberUpdate(chat_id:, chat_member_updated:, ..), itd if itd > 0 -> {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          use <- bool.lazy_guard(
            member.user.is_premium |> option.unwrap(False),
            fn() { next(ctx, upd) },
          )

          let needs_ban = member.user.id > ids_to_delete && !member.user.is_bot
          use <- bool.lazy_guard(!needs_ban, fn() { next(ctx, upd) })

          log.printf("Ban user: {0} {1} id: {2} reason: fresh account", [
            member.user.first_name,
            member.user.last_name |> option.unwrap(""),
            int.to_string(member.user.id),
          ])

          api.ban_chat_member(
            ctx.config.api_client,
            parameters: BanChatMemberParameters(
              chat_id: Int(chat_id),
              user_id: member.user.id,
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

    _, _ -> next(ctx, upd)
  }
}
