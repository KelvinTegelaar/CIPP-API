function Get-CippException {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        $Exception
    )

    [PSCustomObject]@{
        Message         = $Exception.Exception.Message ?? 'Not available'
        NormalizedError = (Get-NormalizedError -message $Exception.Exception.Message) ?? 'Not available'
        RawError        = ($Exception.Exception.Data['RawErrorBody'] ?? $Exception.ErrorDetails.Message ?? $Exception.Exception.Response.Content) ?? 'Not available'
        Position        = $Exception.InvocationInfo.PositionMessage ?? 'Not available'
        StackTrace      = ($Exception.ScriptStackTrace | Out-String) ?? 'Not available'
        ScriptName      = $Exception.InvocationInfo.ScriptName ?? 'Not available'
        LineNumber      = $Exception.InvocationInfo.ScriptLineNumber ?? 'Not available'
        Category        = ($Exception.CategoryInfo.ToString()) ?? 'Not available'
    }
}
