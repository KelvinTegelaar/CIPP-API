function New-CIPPAsyncDeployment {
    <#
    .SYNOPSIS
    Create a trackable async deployment job

    .DESCRIPTION
    Creates one status row per deployment target in the CacheAsyncDeployments table so a
    frontend can poll live progress (rendered by CippApiResults' jobProgress option). Each
    row starts as queued with every step pending. Update progress with
    Set-CIPPAsyncDeploymentStep / Set-CIPPAsyncDeploymentStatus and read it back with
    Get-CIPPAsyncDeployment.

    .PARAMETER JobId
    The job id shared by all rows. Generated when not provided.

    .PARAMETER Names
    One row is created per name — typically the target tenants.

    .PARAMETER StepTitles
    Ordered step titles shown to the user (e.g. one per site template)

    .PARAMETER Source
    Which feature created this job (e.g. SharePointTemplate)
    #>
    [CmdletBinding()]
    param(
        [string]$JobId = (New-Guid).Guid,

        [Parameter(Mandatory = $true)]
        [string[]]$Names,

        [Parameter(Mandatory = $true)]
        [string[]]$StepTitles,

        [string]$Source = 'CIPP'
    )

    $Table = Get-CIPPTable -TableName 'CacheAsyncDeployments'
    $InitialSteps = [string](ConvertTo-Json -Compress -Depth 5 -InputObject @(
            $StepTitles | ForEach-Object {
                @{
                    Title   = [string]$_
                    Status  = 'pending'
                    Message = 'Waiting for deployment to start'
                }
            }
        ))

    foreach ($Name in $Names) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = [string]$JobId
            RowKey       = [string]$Name
            Source       = [string]$Source
            Status       = 'queued'
            Steps        = $InitialSteps
            Logs         = ''
        } -Force
    }
    return $JobId
}
