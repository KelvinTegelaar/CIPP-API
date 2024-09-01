using namespace System.Net

Function Invoke-ExecOffboardTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        $Tenantfilter = $request.body.tenantfilter

        # temp fix -rvdwegen
        $tenantId = (Invoke-RestMethod -Method GET "https://login.windows.net/$Tenantfilter/.well-known/openid-configuration").token_endpoint.Split('/')[3]

        $results = [System.Collections.ArrayList]@()
        $errors = [System.Collections.ArrayList]@()

        if ($request.body.RemoveCSPGuestUsers) {
            # Delete guest users who's domains match the CSP tenants
            try {
                try {
                    $domains = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/domains?`$select=id" -tenantid $env:TenantID -NoAuthCheck:$true).id
                    $CSPGuestUsers = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,mail&`$filter=userType eq 'Guest' and $(($domains | ForEach-Object { "endswith(mail, '$_')" }) -join ' or ')&`$count=true" -tenantid $Tenantfilter -ComplexFilter)
                } catch {
                    $errors.Add("Failed to retrieve guest users: $($_.Exception.message)")
                }

                if ($CSPGuestUsers) {
                    [System.Collections.Generic.List[PSCustomObject]]$BulkRequests = @($CSPGuestUsers | ForEach-Object {
                            @{
                                id     = $($_.id)
                                method = 'DELETE'
                                url    = "/users/$($_.id)"
                            }
                        })

                    $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

                    $results.Add('Successfully removed guest users')
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "CSP Guest users were removed" -Sev "Info" -tenant $TenantFilter
                } else {
                    $results.Add('No guest users found to remove')
                }
            } catch {
                $errors.Add("Something went wrong while deleting guest users: $($_.Exception.message)")
            }
        }

        if ($request.body.RemoveCSPnotificationContacts) {
            # Remove all email adresses that match the CSP tenants domains from the contact properties in /organization
            try {
                try {
                    $domains = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/domains?`$select=id" -tenantid $env:TenantID -NoAuthCheck:$true).id
                } catch {
                    throw "Failed to retrieve CSP domains: $($_.Exception.message)"
                }

                try {
                    # Get /organization data
                    $orgContacts = New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/organization?`$select=id,marketingNotificationEmails,securityComplianceNotificationMails,technicalNotificationMails" -tenantid $TenantFilter

                } catch {
                    throw "Failed to retrieve CSP domains: $($_.Exception.message)"
                }
            } catch {
                $errors.Add("$($_.Exception.message)")
            }

            # foreach through the properties we want to check/update
            @('marketingNotificationEmails','securityComplianceNotificationMails','technicalNotificationMails') | ForEach-Object {
                $property = $_
                $propertyContacts = $orgContacts.($($property))

                if ($propertyContacts -AND ($domains -notcontains ($propertyContacts | ForEach-Object { $_.Split("@")[1] }))) {
                    $newPropertyContent = [System.Collections.Generic.List[object]]($propertyContacts | Where-Object { $domains -notcontains $_.Split("@")[1] })

                    $patchContactBody = if (!($newPropertyContent)) { "{ `"$($property)`" : [] }" } else { [pscustomobject]@{ $property = $newPropertyContent } | ConvertTo-Json }

                    try {
                        New-GraphPostRequest -type PATCH -body $patchContactBody -Uri "https://graph.microsoft.com/v1.0/organization/$($orgContacts.id)" -tenantid $Tenantfilter -ContentType "application/json"
                        $results.Add("Successfully removed notification contacts from $($property): $(($propertyContacts | Where-Object { $domains -contains $_.Split("@")[1] }))")
                        Write-LogMessage -user $ExecutingUser -API $APIName -message "Contacts were removed from $($property)" -Sev "Info" -tenant $TenantFilter
                    } catch {
                        $errors.Add("Failed to update property $($property): $($_.Exception.message)")
                    }
                } else {
                    $results.Add("No notification contacts found in $($property)")
                }
            }
            # Add logic for privacyProfile later - rvdwegen

        }

        if ($request.body.RemoveVendorApps) {
            $request.body.RemoveVendorApps | ForEach-Object {
                try {
                    $delete = (New-GraphPostRequest -type 'DELETE' -Uri "https://graph.microsoft.com/v1.0/serviceprincipals/$($_.value)" -tenantid $Tenantfilter)
                    $results.Add("Successfully removed app $($_.label)")
                    Write-LogMessage -user $ExecutingUser -API $APIName -message "App $($_.label) was removed" -Sev "Info" -tenant $TenantFilter
                } catch {
                    #$results.Add("Failed to removed app $($_.displayName)")
                    $errors.Add("Failed to removed app $($_.label)")
                }
            }
        }

        # All customer tenant specific actions ALWAYS have to be completed before this action!
        if ($request.body.RemoveMultitenantCSPApps) {
            # Remove multi-tenant apps with the CSP tenant as origin
            try {
                $multitenantCSPApps = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$count=true&`$select=displayName,appId,id,appOwnerOrganizationId&`$filter=appOwnerOrganizationId eq $($env:TenantID)" -tenantid $Tenantfilter -ComplexFilter)
                $sortedArray = $multitenantCSPApps | Sort-Object @{Expression = { if ($_.appId -eq $ENV:ApplicationID) { 1 } else { 0 } }; Ascending = $true }
                $sortedArray | ForEach-Object {
                    try {
                        $delete = (New-GraphPostRequest -type 'DELETE' -Uri "https://graph.microsoft.com/v1.0/serviceprincipals/$($_.id)" -tenantid $Tenantfilter)
                        $results.Add("Successfully removed app $($_.displayName)")
                        Write-LogMessage -user $ExecutingUser -API $APIName -message "App $($_.displayName) was removed" -Sev "Info" -tenant $TenantFilter
                    } catch {
                        #$results.Add("Failed to removed app $($_.displayName)")
                        $errors.Add("Failed to removed app $($_.displayName)")
                    }
                }
            } catch {
                #$results.Add("Failed to retrieve multitenant apps, no apps have been removed: $($_.Exception.message)")
                $errors.Add("Failed to retrieve multitenant CSP apps, no apps have been removed: $($_.Exception.message)")
            }
        }

        if ($request.body.TerminateGDAP) {
            # Terminate GDAP relationships
            try {
                $TenantFilter
                $TenantFilter
                $TenantFilter
                $delegatedAdminRelationships = (New-GraphGETRequest -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships?`$filter=(status eq 'active') AND (customer/tenantId eq '$tenantid')" -tenantid $env:TenantID)
                $delegatedAdminRelationships | ForEach-Object {
                    try {
                        $terminate = (New-GraphPostRequest -type 'POST' -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships/$($_.id)/requests" -body '{"action":"terminate"}' -ContentType 'application/json' -tenantid $env:TenantID)
                        $results.Add("Successfully terminated GDAP relationship $($_.displayName) from tenant $TenantFilter")
                        Write-LogMessage -user $ExecutingUser -API $APIName -message "GDAP Relationship $($_.displayName) has been terminated" -Sev "Info" -tenant $TenantFilter
                    } catch {
                        $($_.Exception.message)
                        #$results.Add("Failed to terminate GDAP relationship $($_.displayName): $($_.Exception.message)")
                        $errors.Add("Failed to terminate GDAP relationship $($_.displayName): $($_.Exception.message)")
                    }
                }
            } catch {
                $($_.Exception.message)
                #$results.Add("Failed to retrieve GDAP relationships, no relationships have been terminated: $($_.Exception.message)")
                $errors.Add("Failed to retrieve GDAP relationships, no relationships have been terminated: $($_.Exception.message)")
            }
        }

        if ($request.body.TerminateContract) {
            # Terminate contract relationship
            try {
                $terminate = (New-GraphPostRequest -type 'PATCH' -body '{ "relationshipToPartner": "none" }' -Uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter" -ContentType 'application/json' -scope 'https://api.partnercenter.microsoft.com/user_impersonation' -tenantid $env:TenantID)
                $results.Add('Successfully terminated contract relationship')
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Contract relationship terminated" -Sev "Info" -tenant $TenantFilter
            } catch {
                #$results.Add("Failed to terminate contract relationship: $($_.Exception.message)")
                $errors.Add("Failed to terminate contract relationship: $($_.Exception.message)")
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $body = [pscustomobject]@{
            'Results' = @($results)
            'Errors'  = @($errors)
        }
    } catch {
        $StatusCode = [HttpStatusCode]::OK
        $body = $_.Exception.message
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
