using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$groupobj = $Request.body
$SelectedTenants = if ($Request.body.selectedTenants) { $request.body.selectedTenants.defaultDomainName } else { $Request.body.tenantid }
if ("AllTenants" -in $SelectedTenants) { $SelectedTenants = (Get-Tenants).defaultDomainName }

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$results = foreach ($tenant in $SelectedTenants) {
    try {
        $email = if ($groupobj.domain) { "$($groupobj.username)@$($groupobj.domain)" } else { "$($groupobj.username)@$($tenant)" }
        if ($groupobj.groupType -in "Generic", "azurerole", "dynamic") {
        
            $BodyToship = [pscustomobject] @{
                "displayName"      = $groupobj.Displayname
                "description"      = $groupobj.Description
                "mailNickname"     = $groupobj.username
                mailEnabled        = [bool]$false
                securityEnabled    = [bool]$true
                isAssignableToRole = [bool]($groupobj | Where-Object -Property groupType -EQ "AzureRole")

            } 
            if ($groupobj.membershipRules) {
                $BodyToship | Add-Member  -NotePropertyName "membershipRule" -NotePropertyValue ($groupobj.membershipRules)
                $BodyToship | Add-Member  -NotePropertyName "groupTypes" -NotePropertyValue @("DynamicMembership")
                $BodyToship | Add-Member  -NotePropertyName "membershipRuleProcessingState" -NotePropertyValue "On"
            }
            $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups" -tenantid $tenant -type POST -body (ConvertTo-Json -InputObject $BodyToship -Depth 10)  -verbose
        }
        else {
            $Params = @{ 
                Name                               = $groupobj.Displayname
                Alias                              = $groupobj.username
                Description                        = $groupobj.Description
                PrimarySmtpAddress                 = $email
                Type                               = $groupobj.groupType
                RequireSenderAuthenticationEnabled = [bool]!$groupobj.AllowExternal
            }
            $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet "New-DistributionGroup" -cmdParams $params
        }
        "Successfully created group $($groupobj.displayname) for $($tenant)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Created group $($groupobj.displayname) with id $($GraphRequest.id) " -Sev "Info"

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Group creation API failed. $($_.Exception.Message)" -Sev "Error"
        "Failed to create group. $($groupobj.displayname) for $($tenant) $($_.Exception.Message)"

    }
}
$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
