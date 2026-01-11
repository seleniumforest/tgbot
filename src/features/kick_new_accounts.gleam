import error.{type BotError}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import models/bot_session.{type BotSession}
import sqlight
import storage
import telega/api
import telega/bot.{type Context}
import telega/model/types.{BanChatMemberParameters, Int}
import telega/reply
import telega/update.{type Command, type Update, MessageUpdate}

pub fn command(
  ctx: Context(BotSession, BotError),
  cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let cmd_args =
    cmd.text
    |> string.split(" ")
    |> list.rest()
    |> result.unwrap([])
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
          let _ = reply.with_text(ctx, "Error: please enter valid argument")
          Ok(ctx)
        }
      }
      Ok(ctx)
    }
    Ok(num) -> {
      let current_state = ctx.session.chat_settings.kick_new_accounts
      let new_state = num

      let result = set_state(ctx, current_state, new_state)
      result
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
      let _ = reply.with_text(ctx, "Error: could not set property")
      Error(error.BotError("Could not set property"))
    }
    Ok(_) -> {
      let _ = case new_state {
        ns if ns > 0 ->
          reply.with_text(
            ctx,
            "Success: users with telegram id over "
              <> new_state |> int.to_string()
              <> " will be automatically kicked",
          )
        _ ->
          reply.with_text(
            ctx,
            "Success: users with telegram id over "
              <> current_state |> int.to_string()
              <> " will NOT be kicked anymore",
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
    MessageUpdate(chat_id:, message:, ..), itd if itd > 0 -> {
      case ids_to_delete {
        i if i <= 0 -> next(ctx, upd)
        _ -> {
          message.new_chat_members
          |> option.to_result("No new chat members")
          |> result.unwrap([])
          |> list.filter(fn(m) { m.id > ids_to_delete && !m.is_bot })
          |> list.each(fn(m) {
            echo "Ban user:"
              <> m.first_name
              <> m.last_name |> option.unwrap("")
              <> " id:"
              <> int.to_string(m.id)
              <> " reason: fresh account"

            api.ban_chat_member(
              ctx.config.api_client,
              parameters: BanChatMemberParameters(
                chat_id: Int(chat_id),
                user_id: m.id,
                until_date: option.None,
                revoke_messages: option.Some(True),
              ),
            )
          })

          next(ctx, upd)
        }
      }
    }
    _, _ -> next(ctx, upd)
  }
}
