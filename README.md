## GitHub Actions Heroku-hosted Docker Runner

This project defines a `Dockerfile` to run a [self-hosted](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners) Github Actions runner.

The runner is hosted on [Heroku as a docker image](https://devcenter.heroku.com/articles/build-docker-images-heroku-yml) via `heroku.yml`.

The `start.sh` script, inspired by Michael Herman's [tutorial](https://testdriven.io/blog/github-actions-docker/),
auto registers the newly spun up Heroku dyno as a runner for our GitHub organization.

## Quick Start

**Things you'll need**

- Administrator access to your GitHub organization
- Administrator access to your Heroku organization
- GitHub personal access token
- Heroku API token

The setup requires configurations in both your GitHub organization and your Heroku organization.
You will switch between them throughout the following instructions.

1. In GitHub, enable GitHub Actions for your organization
    - https://github.com/organizations/{YOUR_ORGANIZATION}/settings/actions
    - Under **Policies**
        - Choose **Allow enterprise, and select non-enterprise, actions and reusable workflows**
        - Select **Allow actions created by GitHub**
        - Click **Save**

2. In GitHub, add your Heroku private space's IP addresses to your organization's allow list
    - See [#github-ip-allow-list](https://salesforce-internal.slack.com/archives/C03DY3WAX9Q)
      for instructions on how to formally get the IP addresses added to your organization.
    - If you don't go through the proper process, the IP addresses may be removed by ProdSec.

3. In GitHub, create a personal access token with **admin:org** and **repo** scopes
    > Don't forget to authorize your access token to SSO to your organization

4. In Heroku, create a new app in your private space

5. In Heroku, add two configuration variables to the new app
    - `GITHUB_ACCESS_TOKEN` with the token you created previously
    - `GITHUB_ORGANIZATION` with the name of your organization

6. In a separate browser, sign up for a new Heroku user in order to create an API token (SSO users cannot create tokens)
    - https://signup.heroku.com

7. While logged in as the new Heroku user, generate a new Heroku API key
    - https://dashboard.heroku.com/account
    - Scroll to the **API Key** section then click **Regenerate API Key**

8. While logged in as the Heroku admin, grant the new Heroku user access to **view** and **deploy** to your new app
    - https://dashboard.heroku.com/apps/{YOUR_APP}/access

9. In GitHub, add three organization secrets to store the Heroku information
    - https://github.com/organizations/{YOUR_ORGANIZATION}/settings/secrets/actions
    - `HEROKU_API_KEY` with the api key you created previously
    - `HEROKU_API_USER` with the username who owns the api key
    - `HEROKU_ACTIONS_RUNNER_APP` with the name of your new Heroku app

10. Locally, clone and deploy this repository to your Heroku app

    ```shell
    git clone https://github.com/douglascayers/heroku-github-actions-runner.git
    heroku git:remote --app YOUR_HEROKU_APP
    git push heroku HEAD:main
    ```

11. In Heroku, scale your **runner** resource appropriate for your expected usage
    - https://dashboard.heroku.com/apps/{YOUR_APP}/resources
    - A single dyno can run one GitHub Actions job at a time
    - Recommended: Private-M dyno type scaled to 4 dynos

Voila!

Now when GitHub Action workflows are launched by your repositories, GitHub will orchestrate
with your Heroku-hosted runner to do the work just as if you were using GitHub-hosted runners.

## Keeping Your Runner Updated

GitHub frequently releases updates to the GitHub Action runner package.

If you don't keep the package up-to-date then GitHub won't enqueue jobs.

This project includes a workflow that once a week will rebuild the docker container
and download the latest updates automatically.

## GitHub Runner Script Usage

The following is how to use the `config.sh` and `run.sh` scripts installed by the runner package.

```
Commands:
 ./config.sh         Configures the runner
 ./config.sh remove  Unconfigures the runner
 ./run.sh            Runs the runner interactively. Does not require any options.

Options:
 --help     Prints the help for each command
 --version  Prints the runner version
 --commit   Prints the runner commit
 --check    Check the runner's network connectivity with GitHub server

Config Options:
 --unattended           Disable interactive prompts for missing arguments. Defaults will be used for missing options
 --url string           Repository to add the runner to. Required if unattended
 --token string         Registration token. Required if unattended
 --name string          Name of the runner to configure (default dayers-ltm)
 --runnergroup string   Name of the runner group to add this runner to (defaults to the default runner group)
 --labels string        Extra labels in addition to the default: 'self-hosted,OSX,X64'
 --work string          Relative runner work directory (default _work)
 --replace              Replace any existing runner with the same name (default false)
 --pat                  GitHub personal access token used for checking network connectivity when executing `./run.sh --check`

Examples:
 Check GitHub server network connectivity:
  ./run.sh --check --url <url> --pat <pat>

 Configure a runner non-interactively:
  ./config.sh --unattended --url <url> --token <token>

 Configure a runner non-interactively, replacing any existing runner with the same name:
  ./config.sh --unattended --url <url> --token <token> --replace [--name <name>]

 Configure a runner non-interactively with three extra labels:
  ./config.sh --unattended --url <url> --token <token> --labels L1,L2,L3
```