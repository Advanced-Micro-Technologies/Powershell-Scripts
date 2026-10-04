# ServerBackup-FailureAlert

Emails an alert as soon as Windows Server Backup logs a failure, so a failed
backup gets noticed the day it happens instead of the day someone needs a
restore.

### The problem

Windows Server Backup has no built-in notification. When a scheduled backup
fails, it writes an error to its event log and carries on. Unless someone opens
Event Viewer, the first sign of trouble is often a restore that has nothing to
restore from.

### The approach

A scheduled task watches the Windows Server Backup event log
(`Microsoft-Windows-Backup`, under **Applications and Services Logs → Microsoft
→ Windows → Backup** in Event Viewer). When a Critical or Error event is
written, the task runs `Send-BackupFailureAlert.ps1`, which:

1. Finds the most recent Critical or Error event in that log from the last 24
   hours.
2. Builds an HTML email: a red banner naming the client and server, followed by
   the event time, event ID, and full event message.
3. Sends it over SMTP with STARTTLS and authentication.

If no error is found in the last 24 hours — for example, when the task is run by
hand — the email still goes out, with `n/a` in the event fields and a note that
it may be a manual test. That makes a manual run a simple end-to-end test of the
email settings.

### Configure the script

Fill in the settings block at the top of the script for each server:

| Setting | What to enter |
| --- | --- |
| `$clientName` | Name shown in the subject line and the banner |
| `$smtpServer` | SMTP relay host — for Amazon SES, `email-smtp.<region>.amazonaws.com` |
| `$smtpPort` | `587` (STARTTLS) |
| `$smtpUser` | SMTP username |
| `$smtpPassword` | SMTP password |
| `$to` | Recipient address, or several separated by commas |
| `$from` | Sender address |

The subject line reads `<client> - Local Backup Alert (<server>)`.

**Amazon SES specifics:**

- Use **SES SMTP credentials**, created under **SES → SMTP settings → Create
  SMTP credentials**. They aren't the same as an IAM access key and secret, and
  the IAM pair won't authenticate.
- The `$from` address, or its domain, must be a **verified identity** in SES.
  While the account is still in the SES sandbox, recipients must be verified
  too.
- Use the endpoint for the region where your SES identities are set up.

**Stay on port 587.** The script uses `System.Net.Mail.SmtpClient`, which only
supports STARTTLS. Port 465 (implicit TLS) won't connect.

### Deploy

**1. Copy the script to the server**

```
C:\Company\Scripts\Send-BackupFailureAlert.ps1
```

**2. Unblock it**

A file downloaded from GitHub is tagged as coming from the internet, and the
default `RemoteSigned` execution policy on Windows Server refuses to run it. The
task fails with result `0x1` and nothing visible. Clear the tag at the file's
final location, from an elevated PowerShell session:

```powershell
Unblock-File -Path 'C:\Company\Scripts\Send-BackupFailureAlert.ps1'
```

To confirm, check that the tag is gone — this should return nothing:

```powershell
Get-Item 'C:\Company\Scripts\Send-BackupFailureAlert.ps1' -Stream Zone.Identifier -ErrorAction SilentlyContinue
```

Unblock after the file is in place. Copying a blocked file to a new folder
carries the tag with it.

**3. Lock down the file**

The SMTP password sits in the script in plain text. Once the settings are
filled in, remove inherited permissions so ordinary users can't read it:

```powershell
icacls 'C:\Company\Scripts\Send-BackupFailureAlert.ps1' /inheritance:r `
    /grant:r '*S-1-5-32-544:(F)' '*S-1-5-18:(F)' '<TaskAccount>:(R)'
```

That leaves full control for Administrators (`S-1-5-32-544`) and SYSTEM
(`S-1-5-18`), and read access for the task's account. Replace `<TaskAccount>`
with that account, for example `CONTOSO\svc-backupalert` or `.\Administrator`.

Grant the task account by name even if it's an administrator. With **Run with
highest privileges** unchecked, the task runs with a filtered token, and a
filtered token can't use Administrators group membership to open the file.

**4. Create the scheduled task**

In Task Scheduler, choose **Create Task** (not *Create Basic Task*) and set each
tab as below.

**General**

| Setting | Value |
| --- | --- |
| Name | `Alert - backup failure notification` |
| User account | An administrator account on the server |
| Run whether user is logged on or not | Selected |
| Do not store password | **Checked** |
| Run with highest privileges | Unchecked |
| Hidden | Unchecked |

**Do not store password** is fine here. It limits the task to local resources
for Windows authentication, but the script authenticates to the SMTP relay with
its own username and password, so sending mail isn't affected — and there's no
stored password to break when the account's password changes.

**Triggers** — **New**, then:

| Setting | Value |
| --- | --- |
| Begin the task | **On an event** |
| Settings | **Custom** → **Edit Event Filter…** |
| Advanced settings | All unchecked except **Enabled** |

In the event filter, open the **XML** tab, check **Edit query manually**, and
paste:

```xml
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-Backup">
    <Select Path="Microsoft-Windows-Backup">*[System[(Level=1  or Level=2)]]</Select>
  </Query>
</QueryList>
```

Level 1 is Critical and Level 2 is Error. Warnings and informational events,
including successful backups, don't trigger the task.

**Actions** — **New**, then:

| Setting | Value |
| --- | --- |
| Action | **Start a program** |
| Program/script | `powershell` |
| Add arguments | `-File "C:\Company\Scripts\Send-BackupFailureAlert.ps1"` |

**Conditions** — uncheck everything. In particular, clear **Start the task only
if the computer is on AC power**, which is checked by default on a new task.

**Settings**

| Setting | Value |
| --- | --- |
| Allow task to be run on demand | Checked |
| Run task as soon as possible after a scheduled start is missed | Unchecked |
| If the task fails, restart every | Unchecked |
| Stop the task if it runs longer than | Checked — **1 hour** |
| If the running task does not end when requested, force it to stop | Checked |
| If the task is not scheduled to run again, delete it after | Unchecked |
| If the task is already running | **Do not start a new instance** |

### Test

Right-click the task and choose **Run**, or from PowerShell:

```powershell
Start-ScheduledTask -TaskName 'Alert - backup failure notification'
```

An email should arrive within a few seconds. Unless a backup has failed in the
last 24 hours, it shows `n/a` for the event time and ID along with the
manual-test note.

If nothing arrives, check **Last Run Result** on the task:

| Result | Meaning |
| --- | --- |
| `0x0` | The email was handed to the SMTP server — check spam, and SES sending activity |
| `0x1` | The send failed, or the script didn't run — confirm the file is unblocked, then run the script by hand to see the error |

To see the error directly, run it in an elevated PowerShell session:

```powershell
& 'C:\Company\Scripts\Send-BackupFailureAlert.ps1'
```

### Removal

From an elevated session:

```powershell
Unregister-ScheduledTask -TaskName 'Alert - backup failure notification' -Confirm:$false
Remove-Item 'C:\Company\Scripts\Send-BackupFailureAlert.ps1' -Force
```

### Requirements

- Windows Server with the Windows Server Backup feature and a configured backup
  schedule
- Windows PowerShell 5.1
- An administrator account to run the task
- An SMTP relay that accepts authenticated STARTTLS on port 587 — written for
  Amazon SES

### Notes

**It reports the newest error, not necessarily the one that triggered it.** The
script looks up the most recent Critical or Error event from the last 24 hours
rather than reading the triggering event. With one backup a day, those are the
same event.

**It only alerts on failure.** A backup that stops running altogether — schedule
removed, server off at backup time — logs no error and sends no email. The same
goes for the alert path itself: if the SMTP credentials stop working, the task
fails quietly. Run a manual test from time to time.
