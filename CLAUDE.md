Development notes
-------------------
* `zmeventnotification.pl` is the main Event Server that works with ZoneMinder
* To test it, run it as `sudo -u www-data ./zmeventnotification.pl <options>`
* If you need to access DB, configs etc, access it as `sudo -u www-data`
* Follow DRY principles for coding
* Always write simple code
* hooks/zm_detect.py and its helpers rely on pyzm. pyzm is located at ~/fiddle/pyzm 
* When updating code, tests or documents, if you need to validate functionality, look at pyzm code
* Use conventional commit format for all commits:
  * `feat:` new features
  * `fix:` bug fixes
  * `refactor:` code restructuring without behavior change
  * `docs:` documentation only
  * `chore:` maintenance, config, tooling
  * `test:` adding or updating tests
  * Scope is optional: `feat(install):`, `refactor(config):`, etc.
* NEVER create issues, PRs, or push to the upstream repo (`ZoneMinder/zmeventnotification`). ALL issues, PRs, and pushes MUST go to `pliablepixels/zmeventnotification` (origin).
* If you are fixing bugs or creating new features, the process MUST be:
    - Create a GH issue on `pliablepixels/zmeventnotification` (label it)
    - If developing a feature, create a branch
    - Commit changes referring the issue
    - Wait for the user to confirm before you close the issue


Documentation notes
-------------------
- You are an expert document writer and someone who cares deeply that documentation is clear, easy to follow, user friendly and comprehensive and CORRECT. 
- Analyze RTD docs and make sure the documents fully represent the capabilities of the system, does not have outdated or incomplete things and is user forward.  
- Remember that zm_detect.py leans on pyzm (~/fiddle/pyzm) for most of its functionality. Always validate what is true by reading pyzm code
- Never make changes to CHANGELOG. It is auto generated

When responding to issues or PRs from others
--------------------------------------------
- Never overwrite anyones (including AI agent) comments. Add responses. This is important because I have write permission to upstream repos 
- Always identify yourself as Claude
