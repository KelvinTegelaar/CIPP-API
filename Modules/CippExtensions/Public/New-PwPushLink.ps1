function New-PwPushLink {
    [CmdletBinding()]
    Param(
        $Payload
    )
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).PWPush
    if ($Configuration.Enabled) {
        Set-PwPushConfig -Configuration $Configuration
        $PushParams = @{
            Payload = $Payload
        }
        if ($Configuration.ExpireAfterDays) { $PushParams.ExpireAfterDays = $Configuration.ExpireAfterDays }
        if ($Configuration.ExpireAfterViews) { $PushParams.ExpireAfterViews = $Configuration.ExpireAfterViews }
        if ($Configuration.DeletableByViewer) { $PushParams.DeletableByViewer = $Configuration.DeletableByViewer }
        $Link = New-Push @PushParams | Select-Object Link, LinkRetrievalStep
        if ($Configuration.RetrievalStep) {
            $Link.Link = $Link.LinkRetrievalStep
        }
        $Link | Select-Object -ExpandProperty Link
    } else {
        return $false
    }
}