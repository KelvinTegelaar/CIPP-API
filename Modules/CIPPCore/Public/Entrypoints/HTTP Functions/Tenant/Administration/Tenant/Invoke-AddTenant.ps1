function Invoke-AddTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Action = $Request.Body.Action ?? $Request.Query.Action
    $TenantName = $Request.Body.TenantName ?? $Request.Query.TenantName
    $StatusCode = [HttpStatusCode]::OK

    switch ($Action) {
        'ValidateDomain' {
            # Validate the onmicrosoft.com domain
            $Domain = "$($TenantName).onmicrosoft.com"
            $DomainCheckUri = "https://api.partnercenter.microsoft.com/v1/domains/$Domain"
            Write-Information "Checking $Domain"
            try {
                $null = New-GraphPOSTRequest -type HEAD -uri $DomainCheckUri -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true

                $Body = @{
                    Success = $false
                    Message = "The domain '$Domain' is already in use."
                }
            } catch {
                $Body = @{
                    Success = $true
                }
            }

        }
        'AddTenant' {
            # Fetch the organization id for Tier 2 CSPs
            if ($Request.Body.ResellerType -eq 'Tier2') {
                $OrganizationProfileUri = 'https://api.partnercenter.microsoft.com/v1/profiles/organization'
                try {
                    $OrgResponse = New-GraphPOSTRequest -type GET -uri $OrganizationProfileUri -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true
                    $Request.Body.AssociatedPartnerId = $OrgResponse.id
                } catch {
                    $Body = @{
                        state      = 'Error'
                        resultText = "Failed to retrieve organization profile: $($_.Exception.Message)"
                    }
                    $StatusCode = [HttpStatusCode]::BadRequest
                    break
                }
            }

            $Payload = @{
                enableGDAPByDefault   = $false
                Id                    = $null
                CommerceId            = $null
                CompanyProfile        = @{
                    TenantId    = $null
                    Domain      = '{0}.onmicrosoft.com' -f $TenantName
                    CompanyName = $Request.Body.CompanyName
                    Attributes  = @{ ObjectType = 'CustomerCompanyProfile' }
                }
                BillingProfile        = @{
                    Id             = $null
                    FirstName      = $Request.Body.FirstName
                    LastName       = $Request.Body.LastName
                    Email          = $Request.Body.Email
                    Culture        = 'EN-US'
                    Language       = 'En'
                    CompanyName    = $Request.Body.CompanyName
                    DefaultAddress = @{
                        Country      = $Request.Body.Country
                        Region       = $null
                        City         = $Request.Body.City
                        State        = $Request.Body.State
                        AddressLine1 = $Request.Body.AddressLine1
                        AddressLine2 = $Request.Body.AddressLine2
                        PostalCode   = $Request.Body.PostalCode
                        FirstName    = $Request.Body.FirstName
                        LastName     = $Request.Body.LastName
                        PhoneNumber  = $Request.Body.PhoneNumber
                    }
                    Attributes     = @{ ObjectType = 'CustomerBillingProfile' }
                }
                RelationshipToPartner = 'none'
                AllowDelegatedAccess  = $null
                UserCredentials       = $null
                CustomDomains         = $null
                Attributes            = @{ ObjectType = 'Customer' }
            }

            if ($Request.Body.ResellerType -eq 'Tier2' -and $Request.Body.AssociatedPartnerId) {
                $Payload.AssociatedPartnerId = $Request.Body.AssociatedPartnerId
            }

            $CustomerCreationUri = 'https://api.partnercenter.microsoft.com/v1/customers'
            try {
                $Response = New-GraphPOSTRequest -type POST -uri $CustomerCreationUri -scope 'https://api.partnercenter.microsoft.com/.default' -Body ($Payload | ConvertTo-Json -Depth 10) -NoAuthCheck $true

                $Body = @{
                    state      = 'Success'
                    resultText = "Tenant created successfully. 'Username is $($Response.userCredentials.userName)@{0}.onmicrosoft.com'. Click copy to retrieve the password." -f $TenantName
                    copyField  = $Response.userCredentials.password
                }
            } catch {
                $Body = @{
                    state      = 'Error'
                    resultText = "Failed to create tenant: $($_.Exception.Message)"
                }
                $StatusCode = [HttpStatusCode]::BadRequest
            }
        }
        'ValidateAddress' {
            $AddressPayload = @{
                AddressLine1 = $Request.Body.AddressLine1
                AddressLine2 = $Request.Body.AddressLine2
                City         = $Request.Body.City
                State        = $Request.Body.State
                PostalCode   = $Request.Body.PostalCode
                Country      = $Request.Body.Country
            }

            $AddressValidationUri = 'https://api.partnercenter.microsoft.com/v1/validations/address'
            try {
                $Response = New-GraphPOSTRequest -type POST -uri $AddressValidationUri -scope 'https://api.partnercenter.microsoft.com/.default' -Body ($AddressPayload | ConvertTo-Json -Depth 10) -NoAuthCheck $true

                return @{
                    Status             = 'Success'
                    OriginalAddress    = $Response.originalAddress
                    SuggestedAddresses = $Response.suggestedAddresses
                    ValidationStatus   = $Response.status
                }
            } catch {
                return @{
                    state      = 'Error'
                    resultText = "Address validation failed: $($_.Exception.Message)"
                }
            }
        }
        default {
            return @{
                state      = 'Error'
                resultText = "Invalid action specified: $($Request.Body.Action)"
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
