using namespace System.Net

param($Request, $TriggerMetadata)

Set-CIPPGDAPInviteGroups

$body = @{Results = @('Processing recently activated GDAP relationships') }

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
