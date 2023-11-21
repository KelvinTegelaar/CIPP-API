using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

    $Tenantfilter = $request.body.tenantfilter

    $results = [System.Collections.ArrayList]@()
    $errors = [System.Collections.ArrayList]@()

    if ($request.body.RemoveCSPGuestUsers) {
        # Delete guest users who's domains match the CSP tenants
        try {
            try {
                $domains = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/domains?`$select=id" -tenantid $env:TenantID -NoAuthCheck:$true).id
                $CSPGuestUsers = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,mail&`$filter=userType eq 'Guest' and $(($domains | ForEach-Object { "endswith(mail, '$_')" }) -join " or ")&`$count=true" -tenantid $Tenantfilter -ComplexFilter)    
            } catch {
                $errors.Add("Failed to retrieve guest users: $($_.Exception.message)")
            }

            if ($CSPGuestUsers) {
                [System.Collections.Generic.List[PSCustomObject]]$BulkRequests = @($CSPGuestUsers | ForEach-Object {
                    @{
                        id = $($_.id)
                        method = "DELETE"
                        url = "/users/$($_.id)"
                    }
                })

                $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

                $results.Add("Succesfully removed guest users")
            } else {
                $results.Add("No guest users found to remove")
            }
        } catch {
            $errors.Add("Something went wrong while deleting guest users: $($_.Exception.message)")
        }
    }

    # All customer tenant specific actions ALWAYS have to be completed before this action!
    if ($request.body.RemoveMultitenantApps) {
        # Remove multi-tenant apps with the CSP tenant as origin
        try {
            $multitenantCSPApps = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$select=displayName,appId,id,appOwnerOrganizationId&`$filter=appOwnerOrganizationId eq $($env:TenantID)" -tenantid $Tenantfilter -ComplexFilter)
            $sortedArray = $multitenantCSPApps | Sort-Object @{Expression = { if ($_.appId -eq $env:applicationid) { 1 } else { 0 } }; Ascending = $true }
            $sortedArray | ForEach-Object {
                try {
                    $delete = (New-GraphPostRequest -type "DELETE" -Uri "https://graph.microsoft.com/v1.0/serviceprincipals/$($_.id)" -tenantid $Tenantfilter)
                    $results.Add("Succesfully removed app $($_.displayName)")
                } catch {
                    #$results.Add("Failed to removed app $($_.displayName)")
                    $errors.Add("Failed to removed app $($_.displayName)")
                }
            }
        } catch {
            #$results.Add("Failed to retrieve multitenant apps, no apps have been removed: $($_.Exception.message)")
            $errors.Add("Failed to retrieve multitenant apps, no apps have been removed: $($_.Exception.message)")
        }
    }

    if ($request.body.TerminateGDAP) {
        # Terminate GDAP relationships
        try {
            $delegatedAdminRelationships = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships?`$filter=(status eq 'active') AND (customer/tenantId eq '$TenantFilter')" -tenantid $env:TenantID)
            $delegatedAdminRelationships | ForEach-Object {
                try {
                    $terminate = (New-GraphPostRequest -type "POST" -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships/$($_.id)/requests" -body '{"action":"terminate"}' -ContentType "application/json" -tenantid $env:TenantID)
                    $results.Add("Succesfully terminated GDAP relationship $($_.displayName) from tenant $TenantFilter")
                } catch {
                    #$results.Add("Failed to terminate GDAP relationship $($_.displayName): $($_.Exception.message)")
                    $errors.Add("Failed to terminate GDAP relationship $($_.displayName): $($_.Exception.message)")
                }
            }
        } catch {
            #$results.Add("Failed to retrieve GDAP relationships, no relationships have been terminated: $($_.Exception.message)")
            $errors.Add("Failed to retrieve GDAP relationships, no relationships have been terminated: $($_.Exception.message)")
        }
    }

    if ($request.body.TerminateContract) {
        # Terminate contract relationship
        try {
            $terminate = (New-GraphPostRequest -type "PATCH" -body '{ "relationshipToPartner": "none" }' -Uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter" -ContentType "application/json" -scope "https://api.partnercenter.microsoft.com/user_impersonation" -tenantid $env:TenantID)
            $results.Add("Succesfully terminated contract relationship")
        }
        catch {
            #$results.Add("Failed to terminate contract relationship: $($_.Exception.message)")
            $errors.Add("Failed to terminate contract relationship: $($_.Exception.message)")
        }
    }

    $StatusCode = [HttpStatusCode]::OK
    $body = [pscustomobject]@{
        "Results" = @($results)
        "Errors"  = @($errors)
    }
}
catch {
    $StatusCode = [HttpStatusCode]::OK
    $body = $_.Exception.message
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    })