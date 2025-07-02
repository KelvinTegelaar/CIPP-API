function Invoke-AddTenant {
    <#
    .SYNOPSIS
    Add new tenants to Microsoft 365 partner center
    
    .DESCRIPTION
    Creates new Microsoft 365 tenants through the partner center with domain validation and address verification
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.ReadWrite
        
    .NOTES
    Group: Tenant Management
    Summary: Add Tenant
    Description: Creates new Microsoft 365 tenants through partner center with support for domain validation, address verification, and organization profile retrieval
    Tags: Tenant,Administration,Partner Center
    Parameter: Action (string) [body/query] - Action to perform: ValidateDomain, GetOrganizationProfile, AddTenant, ValidateAddress
    Parameter: TenantName (string) [body/query] - Name for the new tenant (without .onmicrosoft.com)
    Parameter: CompanyName (string) [body] - Company name for the new tenant
    Parameter: FirstName (string) [body] - First name of the billing contact
    Parameter: LastName (string) [body] - Last name of the billing contact
    Parameter: Email (string) [body] - Email address of the billing contact
    Parameter: Country (string) [body] - Country for billing address
    Parameter: City (string) [body] - City for billing address
    Parameter: State (string) [body] - State/province for billing address
    Parameter: AddressLine1 (string) [body] - Primary address line
    Parameter: AddressLine2 (string) [body] - Secondary address line
    Parameter: PostalCode (string) [body] - Postal/ZIP code
    Parameter: PhoneNumber (string) [body] - Phone number for billing contact
    Response: Returns different response objects based on the Action parameter:
    Response: For ValidateDomain:
    Response: - Success (boolean): Whether the domain is available
    Response: - Message (string): Status message about domain availability
    Response: For GetOrganizationProfile:
    Response: - Results (object): Organization profile information from partner center
    Response: For AddTenant:
    Response: - Results (array): Array containing success/error messages and credentials
    Response: For ValidateAddress:
    Response: - Status (string): Validation status
    Response: - OriginalAddress (object): Original address submitted
    Response: - SuggestedAddresses (array): Suggested address corrections
    Response: - ValidationStatus (string): Address validation result
    Example: {
      "Results": [
        {
          "state": "success",
          "resultText": "Tenant created successfully. Username is admin@contoso.onmicrosoft.com. Click copy to retrieve the password.",
          "copyField": "TempPass123!"
        }
      ]
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
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

                $null = New-GraphPOSTRequest -type HEAD -uri $DomainCheckUri -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true -AddedHeaders $Headers

                $Body = @{
                    Success = $false
                    Message = "The domain '$Domain' is already in use."
                }
            }
            catch {
                $Body = @{
                    Success = $true
                }
            }

        }
        'GetOrganizationProfile' {
            $OrganizationProfileUri = 'https://api.partnercenter.microsoft.com/v1/profiles/organization'
            try {
                $OrgResponse = New-GraphGetRequest -uri $OrganizationProfileUri -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true -AddedHeaders $Headers
                # remove the first character from the response and then convert from JSON
                if (!$OrgResponse.id -and $OrgResponse -notmatch '^{') {
                    $OrgResponse = $OrgResponse.Substring(1) | ConvertFrom-Json
                }

                $Body = @{
                    Results = $OrgResponse
                }
            }
            catch {
                $Body = @{
                    Results = @(@{
                            state      = 'error'
                            resultText = "Failed to retrieve organization profile: $($_.Exception.Message)"
                        })
                }
                $StatusCode = [HttpStatusCode]::BadRequest
            }
        }
        'AddTenant' {
            # Get organization profile from graph.microsoft.com
            $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -NoAuthCheck $true

            $CanCreateCustomers = $false
            $PartnerType = $Org.partnerTenantType
            if ($PartnerType -eq 'valueAddedResellerPartnerDelegatedAdmin') {
                # Tier 2 CSP - Get MPN id from partner center
                $PartnerCenterUri = 'https://api.partnercenter.microsoft.com/accountenrollments/v1/accountexternalresourcekeys?accountIds={0}&keyType=mpnId' -f $env:TenantID
                $MPNId = New-GraphGetRequest -uri $PartnerCenterUri -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true
                $AssociatedPartnerId = $MpnId.items[0].keyValue
                Write-Host "Tier 2 CSP - Associated Partner ID: $AssociatedPartnerId"
                $CanCreateCustomers = $true
            }
            elseif ($PartnerType -eq 'resellerPartnerDelegatedAdmin') {
                # Tier 1 CSP
                $CanCreateCustomers = $true
            }

            if (!$CanCreateCustomers) {
                $Body = @{
                    $Results = @(@{
                            state      = 'error'
                            resultText = 'You do not have permission to create customers. You must be a Tier 1 or Tier 2 CSP.'
                        })
                }
            }
            else {
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

                if ($AssociatedPartnerId) {
                    $Payload.AssociatedPartnerId = $AssociatedPartnerId
                }

                $CustomerCreationUri = 'https://api.partnercenter.microsoft.com/v1/customers'
                Write-Warning "Posting to $CustomerCreationUri"
                Write-Information ($Payload | ConvertTo-Json -Depth 10)

                try {
                    # not doing this yet

                    #$Response = New-GraphPOSTRequest -type POST -uri $CustomerCreationUri -scope 'https://api.partnercenter.microsoft.com/.default' -Body ($Payload | ConvertTo-Json -Depth 10) -NoAuthCheck $true -AddedHeaders $Headers

                    # Sample response
                    $Response = @{
                        userCredentials = @{
                            userName = 'test'
                            password = 'this_is_not_a_real_password'
                        }
                    }
                    ####


                    $Body = @{
                        Results = @(@{
                                state      = 'success'
                                resultText = "Tenant created successfully. 'Username is $($Response.userCredentials.userName)@{0}.onmicrosoft.com'. Click copy to retrieve the password." -f $TenantName
                                copyField  = $Response.userCredentials.password
                            })
                    }
                }
                catch {
                    $Body = @{
                        Results = @(@{
                                state      = 'error'
                                resultText = "Failed to create tenant: $($_.Exception.Message)"
                            })
                    }
                    $StatusCode = [HttpStatusCode]::BadRequest
                }
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
            }
            catch {
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
