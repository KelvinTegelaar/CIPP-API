using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


try {
    $Tenant = $request.query.TenantFilter
    $SearchParams = @{
        StartDate = (Get-Date).AddDays( - $($request.query.days))
        EndDate   = Get-Date
    }
    
    if ($null -ne $request.query.recipient) { $Searchparams.Add('RecipientAddress', $($request.query.recipient)) }
    if ($null -ne $request.query.sender) { $Searchparams.Add('SenderAddress', $($request.query.sender)) }
    $type = $request.query.Tracedetail    
    $upn = "notRequired@required.com"
    $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenant).Authorization -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Get-messagetrace$type"
    $trace = if ($Request.Query.Tracedetail) {
        Get-MessageTraceDetail -MessageTraceId $Request.Query.ID -RecipientAddress $request.query.recipient -erroraction stop | Select-Object Event, Action, Detail, @{ Name = 'Date'; Expression = { $_.Date.Tostring('s') } }
    }
    else {
        Get-MessageTrace @SearchParams -erroraction stop | Select-Object MessageTraceId, Status, Subject, RecipientAddress, SenderAddress, @{ Name = 'Date'; Expression = { $_.Received.tostring('s') } }
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant)  -message "Executed message trace" -Sev "Info"

    }
    Get-PSSession | Remove-PSSession
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed executing messagetrace. Error: $($_.Exception.Message)" -Sev "Error"
    $trace = @{Status = "Failed to retrieve message trace $($_.Exception.Message)" }
    Get-PSSession | Remove-PSSession
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($trace)
    })
