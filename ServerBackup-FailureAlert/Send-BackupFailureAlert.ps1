# Backup failure alert
# Run by Task Scheduler on Level 1/2 events in the Microsoft-Windows-Backup log.
 
# ----- Settings (change per server) -----
$clientName   = ""
$smtpServer   = ""
$smtpPort     = 587
$smtpUser     = ""
$smtpPassword = ""
$to           = ""
$from         = ""
 
# ----- Get the most recent backup error -----
$serverName = $env:COMPUTERNAME
 
$backupEvent = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-Backup'
    Level     = 1, 2
    StartTime = (Get-Date).AddHours(-24)
} -MaxEvents 1 -ErrorAction SilentlyContinue
 
if ($backupEvent) {
    $eventTime    = $backupEvent.TimeCreated.ToString('yyyy-MM-dd h:mm tt')
    $eventId      = $backupEvent.Id
    $eventMessage = [System.Net.WebUtility]::HtmlEncode($backupEvent.Message) -replace "`r?`n", "<br />"
}
else {
    $eventTime    = "n/a"
    $eventId      = "n/a"
    $eventMessage = "No backup error event was found in the last 24 hours. This may be a manual test."
}
 
# ----- Build the email -----
$subject = "$clientName - Local Backup Alert ($serverName)"
 
$body = @"
<html>
<body style="font-family: Segoe UI, Arial, sans-serif;">
<table style="width: 100%; height: 200px; background-color: red; color: black; text-align: center; font-size: 20px;">
<tr>
<td>$clientName Server ($serverName)<br />The server backup has failed</td>
</tr>
</table>
<table style="margin-top: 16px; font-size: 14px;">
<tr><td style="padding: 4px 16px 4px 0; vertical-align: top;"><b>Event time</b></td><td>$eventTime</td></tr>
<tr><td style="padding: 4px 16px 4px 0; vertical-align: top;"><b>Event ID</b></td><td>$eventId</td></tr>
<tr><td style="padding: 4px 16px 4px 0; vertical-align: top;"><b>Message</b></td><td>$eventMessage</td></tr>
</table>
</body>
</html>
"@
 
$message = New-Object System.Net.Mail.MailMessage
$message.From = $from
$message.To.Add($to)
$message.Subject = $subject
$message.Body = $body
$message.IsBodyHtml = $true
 
# ----- Send -----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
 
$smtp = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
$smtp.EnableSsl = $true
$smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPassword)
 
$exitCode = 0
try {
    $smtp.Send($message)
}
catch {
    Write-Error "Failed to send backup alert: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    $message.Dispose()
    $smtp.Dispose()
}
 
exit $exitCode