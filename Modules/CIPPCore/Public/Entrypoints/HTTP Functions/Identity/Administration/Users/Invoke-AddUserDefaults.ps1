function Invoke-AddUserDefaults {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        # Extract data from request body - matching CippAddEditUser.jsx field names
        $TenantFilter = $Request.Body.tenantFilter
        $TemplateName = $Request.Body.templateName
        $DefaultForTenant = $Request.Body.defaultForTenant

        Write-Host "Creating template '$TemplateName' for tenant: $TenantFilter"

        # User fields
        $GivenName = $Request.Body.givenName
        $Surname = $Request.Body.surname
        $DisplayName = $Request.Body.displayName

        # Handle autocomplete fields - extract value if it's an object
        $UsernameFormat = if ($Request.Body.usernameFormat -is [string]) {
            $Request.Body.usernameFormat
        } else {
            $Request.Body.usernameFormat.value
        }

        $PrimDomain = if ($Request.Body.primDomain -is [string]) {
            $Request.Body.primDomain
        } else {
            $Request.Body.primDomain.value
        }

        $AddedAliases = $Request.Body.addedAliases

        # Settings
        $Autopassword = $Request.Body.Autopassword
        $Password = $Request.Body.password
        $MustChangePass = $Request.Body.MustChangePass

        $UsageLocation = if ($Request.Body.usageLocation -is [string]) {
            $Request.Body.usageLocation
        } else {
            $Request.Body.usageLocation.value
        }

        $Licenses = $Request.Body.licenses
        $RemoveLicenses = $Request.Body.removeLicenses

        # Job and Location fields
        $JobTitle = $Request.Body.jobTitle
        $StreetAddress = $Request.Body.streetAddress
        $City = $Request.Body.city
        $State = $Request.Body.state
        $PostalCode = $Request.Body.postalCode
        $Country = $Request.Body.country
        $CompanyName = $Request.Body.companyName
        $Department = $Request.Body.department

        # Contact fields
        $MobilePhone = $Request.Body.mobilePhone
        $BusinessPhones = $Request.Body.'businessPhones[0]'
        $OtherMails = $Request.Body.otherMails

        # User relations
        $SetManager = $Request.Body.setManager
        $SetSponsor = $Request.Body.setSponsor
        $CopyFrom = $Request.Body.copyFrom

        # Create template object with all fields from CippAddEditUser
        $TemplateObject = @{
            tenantFilter     = $TenantFilter
            templateName     = $TemplateName
            defaultForTenant = [bool]$DefaultForTenant
            givenName        = $GivenName
            surname          = $Surname
            displayName      = $DisplayName
            usernameFormat   = $UsernameFormat
            primDomain       = $PrimDomain
            addedAliases     = $AddedAliases
            Autopassword     = $Autopassword
            password         = $Password
            MustChangePass   = $MustChangePass
            usageLocation    = $UsageLocation
            licenses         = $Licenses
            removeLicenses   = $RemoveLicenses
            jobTitle         = $JobTitle
            streetAddress    = $StreetAddress
            city             = $City
            state            = $State
            postalCode       = $PostalCode
            country          = $Country
            companyName      = $CompanyName
            department       = $Department
            mobilePhone      = $MobilePhone
            businessPhones   = $BusinessPhones
            otherMails       = $OtherMails
            setManager       = $SetManager
            setSponsor       = $SetSponsor
            copyFrom         = $CopyFrom
        }

        # Generate GUID for the template
        $GUID = (New-Guid).GUID

        # Convert to JSON
        $JSON = ConvertTo-Json -InputObject $TemplateObject -Depth 100 -Compress

        # Store in table
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'UserDefaultTemplate'
            GUID         = "$GUID"
        }

        $Result = "Created User Default Template '$($TemplateName)' with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create User Default Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })
}
