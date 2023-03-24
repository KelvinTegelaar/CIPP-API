using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$UserID = $Request.Query.UserID
            $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet "Get-InboxRule" -cmdParams @{mailbox = $UserID} | Select-Object
            @{ Name = 'DisplayName'; Expression = { $_.displayName} },
            @{ Name = 'Description'; Expression = { $_.Description} },
            @{ Name = 'Redirect To'; Expression = { $_.RedirectTo} },
            @{ Name = 'Copy To Folder'; Expression = { $_.CopyToFolder} },
            @{ Name = 'Move To Folder'; Expression = { $_.MoveToFolder} },
            @{ Name = 'Soft Delete Message'; Expression = { $_.SoftDeleteMessage} },
            @{ Name = 'Delete Message'; Expression = { $_.DeleteMessage} }

    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to retrieve mailbox rules $($request.query.id): $($_.Exception.message) " -Sev 'Error' -tenant $TenantFilter
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $(Get-NormalizedError -message $_.Exception.message)
            })
    }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = @($GraphRequest)
})