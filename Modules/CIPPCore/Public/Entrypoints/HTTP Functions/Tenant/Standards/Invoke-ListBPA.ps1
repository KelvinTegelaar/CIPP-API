using namespace System.Net

Function Invoke-ListBPA {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BestPracticeAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    # Write-LogMessage -headers $Request.Headers -API $APINAME -message "Accessed this API" -Sev "Debug"

    $Table = get-cipptable 'cachebpav2'
    $name = $Request.query.Report
    if ($name -eq $null) { $name = 'CIPP Best Practices v1.5 - Table view' }

    # Get all possible JSON files for reports, find the correct one, select the Columns
    $JSONFields = @()
    $BPATemplateTable = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'BPATemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @BPATemplateTable -Filter $Filter).JSON | ConvertFrom-Json

    $Templates | ForEach-Object {
        $Template = $_
        if ($Template.Name -eq $NAME) {
            $JSONFields = $Template.Fields | Where-Object { $_.StoreAs -eq 'JSON' } | ForEach-Object { $_.name }
            $Columns = $Template.fields.FrontendFields | Where-Object -Property name -NE $null
            $Style = $Template.Style
        }
    }


    if ($Request.query.tenantFilter -ne 'AllTenants' -and $Style -eq 'Tenant') {
        $CustomerId = (Get-Tenants -TenantFilter $Request.query.tenantFilter).customerId
        $mergedObject = New-Object pscustomobject
        $Data = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$CustomerId'") | ForEach-Object {
            $row = $_
            $JSONFields | ForEach-Object {
                $jsonContent = $row.$_
                if (![string]::IsNullOrEmpty($jsonContent) -and $jsonContent -ne 'FAILED') {
                    try {
                        $row.$_ = $jsonContent | ConvertFrom-Json -Depth 15
                    } catch {
                    }
                }
            }
            $row.PSObject.Properties | ForEach-Object {
                Write-Host "Adding $($_.Name) to mergedObject"
                $mergedObject | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force
            }
        }

        $Data = $mergedObject
    } else {
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        $Tenants = Get-Tenants -IncludeErrors
        if ($AllowedTenants -notcontains 'AllTenants') {
            $Tenants = $Tenants | Where-Object -Property customerId -In $AllowedTenants
        }
        Write-Information ($tenants.defaultDomainName | ConvertTo-Json)
        $Data = (Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$NAME'") | ForEach-Object {
            $row = $_
            $JSONFields | ForEach-Object {
                $jsonContent = $row.$_
                if (![string]::IsNullOrEmpty($jsonContent) -and $jsonContent -ne 'FAILED') {
                    try {
                        $row.$_ = $jsonContent | ConvertFrom-Json -Depth 15
                    } catch {
                    }
                }
            }
            $row | Where-Object -Property PartitionKey -In $Tenants.customerId
        }


    }

    $Results = [PSCustomObject]@{
        Data    = @($Data)
        Columns = @($Columns)
        Keys    = $Data | ForEach-Object {
            $_.PSObject.Properties |
            Where-Object { $_.Name -ne 'PartitionKey' -and $_.Name -ne 'RowKey' -and $_.Name -ne 'Timestamp' } |
            ForEach-Object { $_.Name }
        } | Select-Object -Unique
        Style   = $Style
    }

    if (!$Results) {
        $Results = @{
            Columns = @( value = 'Results'; name = 'Results')
            Data    = @(@{ Results = 'The BPA has not yet run.' })
            Keys    = @()
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = (ConvertTo-Json -Depth 15 -InputObject $Results)
        })

}
