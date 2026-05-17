Development notes
-------------------
* `zmeventnotification.pl` is the main Event Server that works with ZoneMinder
* To test it, run it as `sudo -u www-data ./zmeventnotification.pl <options>`
* If you need to access DB, configs etc, access it as `sudo -u www-data`
* Follow DRY principles for coding
* Always write simple code
* hooks/zm_detect.py and its helpers rely on pyzmNg. pyzmNg is located at ~/fiddle/pyzmNg 
* When updating code, tests or documents, if you need to validate functionality, look at pyzmNg code
* Use conventional commit format for all commits:
  * `feat:` new features
  * `fix:` bug fixes
  * `refactor:` code restructuring without behavior change
  * `docs:` documentation only
  * `chore:` maintenance, config, tooling
  * `test:` adding or updating tests
  * Scope is optional: `feat(install):`, `refactor(config):`, etc.
* The canonical repo is `ZoneMinder/zmeventnotificationNg` (origin). All issues, PRs, and pushes go there.
* If you are fixing bugs or creating new features, the process MUST be:
    - Create a GH issue on `ZoneMinder/zmeventnotificationNg` (label it)
    - If developing a feature, create a branch
    - Commit changes referring the issue
    - Wait for the user to confirm before you close the issue


Documentation notes
-------------------
- You are an expert document writer and someone who cares deeply that documentation is clear, easy to follow, user friendly and comprehensive and CORRECT.
- Analyze RTD docs and make sure the documents fully represent the capabilities of the system, does not have outdated or incomplete things and is user forward.
- Remember that zm_detect.py leans on pyzmNg (~/fiddle/pyzmNg) for most of its functionality. Always validate what is true by reading pyzmNg code
- Never make changes to CHANGELOG. It is auto generated
- When adding, removing, or changing ANY config key, you MUST update:
  * The config reference table in `docs/guides/config.rst` (under "Complete Hook Config Reference")
  * The example config `hook/objectconfig.example.yml`
  * `hook/zmes_hook_helpers/common_params.py` (for flat keys)
  * Any code examples in `docs/guides/hooks.rst` that reference the key
  * pyzmNg docs if the key is consumed by pyzmNg

When responding to issues or PRs from others
--------------------------------------------
- Never overwrite anyones (including AI agent) comments. Add responses. This is important because I have write permission to upstream repos 
- Always identify yourself as Claude
