import dot_env as dot
import dot_env/env
import error.{type BotError}
import features/help
import features/kick_new_accounts
import features/remove_comments_nonmembers
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option
import gleam/result
import gleam/string
import models/bot_session.{type BotSession}
import storage
import telega
import telega/bot.{type Context}
import telega/polling
import telega/router
import telega/update.{type Update}

pub fn main() {
  dot.new()
  |> dot.load

  let db = storage.init()

  let router =
    router.new("default")
    |> router.use_middleware(inject_chat_settings(db))
    |> router.on_custom(fn(_) { True }, handle_update)
    |> router.on_command("kickNewAccounts", kick_new_accounts.command)
    |> router.on_commands(["help", "start"], help.command)
    |> router.on_command(
      "removeCommentsNonMembers",
      remove_comments_nonmembers.command,
    )

  let assert Ok(token) = env.get_string("BOT_TOKEN")
  let assert Ok(bot) =
    telega.new_for_polling(token:)
    |> telega.with_router(router)
    |> telega.with_session_settings(
      bot.SessionSettings(
        persist_session: fn(_key, session) { Ok(session) },
        get_session: fn(_key) { bot_session.default(db) |> option.Some |> Ok },
        default_session: fn() { bot_session.default(db) },
      ),
    )
    |> telega.init_for_polling()

  let assert Ok(poller) = polling.start_polling_default(bot)

  polling.wait_finish(poller)
}

fn handle_update(
  ctx: Context(BotSession, BotError),
  upd: Update,
) -> Result(Context(BotSession, BotError), BotError) {
  process.spawn_unlinked(fn() {
    use ctx, _upd <- kick_new_accounts.checker(ctx, upd)
    use _ctx, _upd <- remove_comments_nonmembers.checker(ctx, upd)
    Nil
  })
  Ok(ctx)
}

fn inject_chat_settings(db) {
  fn(handler) {
    fn(ctx: bot.Context(BotSession, BotError), update: update.Update) {
      let chat =
        result.try_recover(storage.get_chat(db, ctx.update.chat_id), fn(err) {
          case err {
            storage.EmptyDataError -> {
              io.println(
                "Creating chat settings for new key "
                <> ctx.update.chat_id |> int.to_string,
              )
              storage.create_chat(db, ctx.update.chat_id)
            }
            _ -> Error(err)
          }
        })

      case chat {
        Error(e) -> {
          io.println_error(
            "ERROR: Could not get chat settings for chat "
            <> ctx.key
            <> " error: "
            <> e |> string.inspect
            <> " Processing with default handler. This is NOT normal behaviour",
          )
          handler(ctx, update)
        }
        Ok(c) -> {
          let modified_ctx =
            bot.Context(..ctx, session: bot_session.BotSession(c, db))
          handler(modified_ctx, update)
        }
      }
    }
  }
}
