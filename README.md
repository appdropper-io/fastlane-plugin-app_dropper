# fastlane-plugin-app_dropper

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-app_dropper)

Upload the build your lane just produced to [App Dropper](https://appdropper.io) and get a shareable install link back.

## Getting started

```bash
fastlane add_plugin app_dropper
```

Generate an API token under **Settings → API tokens** in your App Dropper dashboard, and export it:

```bash
export APPDROPPER_TOKEN="adp_…"
```

Each token is scoped to a single app and carries one scope, `upload:builds` — it cannot delete builds, manage testers, read billing, or reach another app.

## Usage

With no arguments, the action uploads whatever the lane most recently built — `IPA_OUTPUT_PATH`, falling back to `GRADLE_APK_OUTPUT_PATH`:

```ruby
lane :beta do
  build_app(scheme: "MyApp", export_method: "ad-hoc")
  app_dropper
end
```

Or spell it out:

```ruby
lane :beta do
  build_app(scheme: "MyApp", export_method: "ad-hoc")

  app_dropper(
    api_token: ENV["APPDROPPER_TOKEN"],
    file: lane_context[SharedValues::IPA_OUTPUT_PATH],
    release_notes: last_git_commit[:message],
    tag: "adhoc"
  )
end
```

### Android

```ruby
lane :beta do
  gradle(task: "assemble", build_type: "Release")

  app_dropper(
    file: lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH],
    release_notes: last_git_commit[:message]
  )
end
```

## Options

| Option | Environment variable | Default |
|---|---|---|
| `api_token` | `APPDROPPER_TOKEN` | required |
| `file` | `APPDROPPER_FILE` | the lane's `.ipa`, else its `.apk` |
| `release_notes` | `APPDROPPER_RELEASE_NOTES` | empty |
| `tag` | `APPDROPPER_TAG` | `beta` |
| `timeout` | `APPDROPPER_TIMEOUT` | `600` seconds |
| `api_url` | `APPDROPPER_API_URL` | `https://appdropper.io/api/v1` |

`api_token` is declared sensitive, so fastlane redacts it from logs and from the run summary.

## Return value and lane context

The action returns the install link, and also sets:

| Lane context key | Contains |
|---|---|
| `APP_DROPPER_INSTALL_URL` | Public install link |
| `APP_DROPPER_BUILD_ID` | Identifier of the new build |
| `APP_DROPPER_QR_URL` | PNG QR code for the install link |
| `APP_DROPPER_VERSION` | Version string read out of the binary |

```ruby
url = app_dropper
slack(message: "New iOS beta is up: #{url}")
```

## Switching from Diawi

The action is deliberately shaped like the community `diawi` plugin, so the change is mechanical:

```ruby
# Before
diawi(
  token: ENV["DIAWI_TOKEN"],
  file: lane_context[SharedValues::IPA_OUTPUT_PATH],
  comment: last_git_commit[:message]
)

# After
app_dropper(
  api_token: ENV["APPDROPPER_TOKEN"],
  file: lane_context[SharedValues::IPA_OUTPUT_PATH],
  release_notes: last_git_commit[:message]
)
```

Both block the lane until the build is processed and both return a link. App Dropper additionally groups builds into an app with full version history, notifies your registered testers by email and push, and keeps builds for 7 days on free or 30 on Pro (indefinitely if you pin one).

## What your testers are told

A successful upload emails and push-notifies everyone on the app with *"A new
version is available for {your app}"* — the account the token belongs to
included, since nobody watched the lane run. Running inside CI, the plugin
reads the runner's environment (GitHub Actions, GitLab CI, Bitrise, CircleCI,
Bitbucket Pipelines, Codemagic, Jenkins and friends) so that email can name the
branch and commit and link back to the build. Set `APPDROPPER_NO_CI_INFO=1` to
leave those details out.

## How it works

The binary never passes through the API. The action reserves an upload (which is where every plan limit and quota is applied), streams the file straight to Google Cloud Storage, then waits for the server to parse it. That's what keeps a 500 MB `.ipa` clear of the request-size ceilings every HTTP API has.

No runtime dependencies — everything uses Ruby's standard library, so installing this plugin can't drag a conflicting HTTP gem into your `Gemfile.lock`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Docs

- [Fastlane guide](https://appdropper.io/help/fastlane-plugin)
- [CI/CD setup guide](https://appdropper.io/help/ci-cd-uploads)
- [REST API reference](https://appdropper.io/help/api)

## License

MIT
