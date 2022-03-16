using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$UserID = $request.Query.UserID
$Tenantfilter = $request.Query.tenantfilter
Write-Information "My username is $UserID"
Write-Information "My tenantfilter is $Tenantfilter"

try {
    $GetCalParam = @{Identity = $UserID; FolderScope = 'Calendar' }
    $CalendarFolder = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Get-MailboxFolderStatistics" -cmdParams $GetCalParam | Select-Object -First 1
    $CalParam = @{Identity = "$($UserID):\$($CalendarFolder.name)" }
    $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Get-MailboxFolderPermission" -cmdParams $CalParam
    Log-request -API 'List Calendar Permissions' -tenant $tenantfilter -message "Calendar permissions listed for $($tenantfilter)" -sev Debug
    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
