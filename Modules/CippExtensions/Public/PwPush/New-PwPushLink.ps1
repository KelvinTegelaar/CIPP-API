function New-PwPushLink {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        $Payload
    )
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).PWPush
    if ($Configuration.Enabled -eq $true) {
        Set-PwPushConfig -Configuration $Configuration
        $PushParams = @{
            Payload = $Payload
        }
        if ($Configuration.ExpireAfterDays) { $PushParams.ExpireAfterDays = $Configuration.ExpireAfterDays }
        if ($Configuration.ExpireAfterViews) { $PushParams.ExpireAfterViews = $Configuration.ExpireAfterViews }
        if ($Configuration.DeletableByViewer) { $PushParams.DeletableByViewer = $Configuration.DeletableByViewer }
        if ($Configuration.AccountId) { $PushParams.AccountId = $Configuration.AccountId.value }
        try {
            if ($PSCmdlet.ShouldProcess('Create a new PwPush link')) {
                $Link = New-Push @PushParams
                if ($Configuration.RetrievalStep) {
                    return $Link.LinkRetrievalStep
                }
                return $Link.Link
            }
        } catch {
            $LogData = [PSCustomObject]@{
                'Response'  = $Link
                'Exception' = Get-CippException -Exception $_
            }
            Write-LogMessage -API PwPush -Message "Failed to create a new PwPush link: $($_.Exception.Message)" -Sev 'Error' -LogData $LogData
            throw 'Failed to create a new PwPush link, check the log book for more details'
        }
    } else {
        return $false
    }
}
