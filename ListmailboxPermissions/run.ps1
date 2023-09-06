using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter

Write-Host "Tenant Filter: $TenantFilter"
try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Request.Query.UserID)
    $base64IdentityParam = [Convert]::ToBase64String($Bytes)   
    $PermsRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox('$($Request.Query.UserID)')/MailboxPermission" -Tenantid $tenantfilter -scope ExchangeOnline 
    $PermsRequest2 = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Recipient('$base64IdentityParam')?`$expand=RecipientPermission&isEncoded=true" -Tenantid $tenantfilter -scope ExchangeOnline 
    $PermRequest3 = New-ExoRequest -Anchor $Request.Query.UserID -tenantid $Tenantfilter -cmdlet "Get-Mailbox" -cmdParams @{Identity = $($Request.Query.UserID); }

    $GraphRequest = foreach ($Perm in $PermsRequest, $PermsRequest2.RecipientPermission, $PermRequest3) {

        if ($perm.Trustee) {
            $perm | Where-Object Trustee | ForEach-Object { [PSCustomObject]@{
                    User        = $_.Trustee
                    Permissions = $_.accessRights
                }
            }
            
        }
        if ($perm.PermissionList) {
            $perm |  Where-Object User | ForEach-Object { [PSCustomObject]@{
                    User        = $_.User
                    Permissions = $_.PermissionList.accessRights -join ', '
                }        
            }
        }
        if ($perm.GrantSendonBehalfTo -ne $null) {
            $perm.GrantSendonBehalfTo | ForEach-Object { [PSCustomObject]@{
                    User        = $_
                    Permissions = "SendOnBehalf"
                }        
            }
        }
    }
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


