function Get-CIPPAlertQuarantineReleaseRequests {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $HasLicense = Test-CIPPStandardLicense -StandardName 'QuarantineReleaseRequests' -TenantFilter $TenantFilter -RequiredCapabilities @(
        'EXCHANGE_S_STANDARD',
        'EXCHANGE_S_ENTERPRISE',
        'EXCHANGE_S_STANDARD_GOV',
        'EXCHANGE_S_ENTERPRISE_GOV',
        'EXCHANGE_LITE'
    )

    if (-not $HasLicense) {
        return
    }

    try {
        $RequestedReleases = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams @{ PageSize = 1000; ReleaseStatus = 'Requested' } -ErrorAction Stop | Select-Object -ExcludeProperty *data.type*

        if ($RequestedReleases) {
            # Get the CIPP URL for the Quarantine link
            $CippConfigTable = Get-CippTable -tablename Config
            $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
            $CIPPUrl = 'https://{0}' -f $CippConfig.Value

            $AlertData = foreach ($Message in $RequestedReleases) {
                [PSCustomObject]@{
                    Identity          = $Message.Identity
                    MessageId         = $Message.MessageId
                    Subject           = $Message.Subject
                    SenderAddress     = $Message.SenderAddress
                    RecipientAddress  = $Message.RecipientAddress
                    Type              = $Message.Type
                    PolicyName        = $Message.PolicyName
                    ReleaseStatus     = $Message.ReleaseStatus
                    ReceivedTime      = $Message.ReceivedTime
                    QuarantineViewUrl = "$CIPPUrl/email/administration/quarantine?tenantFilter=$TenantFilter"
                    Tenant            = $TenantFilter
                }
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        Write-AlertMessage -tenant $TenantFilter -message "QuarantineReleaseRequests: $(Get-NormalizedError -message $_.Exception.Message)"
    }
}
