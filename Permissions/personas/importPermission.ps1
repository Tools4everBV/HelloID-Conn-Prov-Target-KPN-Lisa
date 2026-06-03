#################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Personas-Import
# Correlate to permission
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-KPNLisaError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {

            $errorObjectConverted = $ErrorObject.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $errorObjectConverted.Error) {
                if ($null -ne $errorObjectConverted.Error.Message) {
                    $httpErrorObj.FriendlyMessage = $errorObjectConverted.Error.Message

                    if ($null -ne $errorObjectConverted.Error.Code) { 
                        $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage + ". Error code: $($errorObjectConverted.Error.Code)"
                    }

                    if ($null -ne $errorObjectConverted.ErrorDetails) { 
                        $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage + ". Additional details: $($errorObjectConverted.ErrorDetails | ConvertTo-Json)"
                    }
                }
                else {
                    $httpErrorObj.FriendlyMessage = $errorObjectConverted.Error
                }
            }
            else {
                $httpErrorObj.FriendlyMessage = $ErrorObject
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Convert-StringToBoolean($obj) {
    foreach ($property in $obj.PSObject.Properties) {
        $value = $property.Value
        if ($value -is [string]) {
            try {
                $obj.$($property.Name) = [System.Convert]::ToBoolean($value)
            }
            catch {
                # Handle cases where conversion fails
                $obj.$($property.Name) = $value
            }
        }
    }
    return $obj
}
#endregion functions

try {
    Write-Information 'Starting target permission import for [KPN Lisa Personas]'

    #region Create access token
    $actionMessage = "creating access token"
    
    $createAccessTokenBody = @{
        grant_type    = "client_credentials"
        client_id     = $actionContext.Configuration.EntraIDAppId
        client_secret = $actionContext.Configuration.EntraIDAppSecret
        scope         = $actionContext.Configuration.KPNMWPScope
    }
    
    $createAccessTokenSplatParams = @{
        Uri             = "https://login.microsoftonline.com/$($actionContext.Configuration.EntraIDTenantID)/oauth2/v2.0/token/"
        Headers         = $headers
        Method          = "POST"
        ContentType     = "application/x-www-form-urlencoded"
        UseBasicParsing = $true
        Body            = $createAccessTokenBody
        Verbose         = $false
        ErrorAction     = "Stop"
    }
    
    $createAccessTokenResponse = Invoke-RestMethod @createAccessTokenSplatParams
    
    Write-Information "Created access token. Expires in: $($createAccessTokenResponse.expiresIn | ConvertTo-Json)"
    #endregion Create access token
    
    #region Create headers
    $actionMessage = "creating headers"
    
    $headers = @{
        "Accept"          = "application/json"
        "Content-Type"    = "application/json;charset=utf-8"
        "Mwp-Api-Version" = "1.0"
    }
    
    Write-Information "Created headers. Result (without Authorization): $($headers | ConvertTo-Json)."

    # Add Authorization after printing splat
    $headers['Authorization'] = "Bearer $($createAccessTokenResponse.access_token)"
    #endregion Create headers

    #region Get Personas
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/personas
    $actionMessage = "querying personas"

    $getKPNLisaPersonasSplatParams = @{
        Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/personas"
        Method      = "GET"
        Verbose     = $false
        ErrorAction = "Stop"
    }

    Write-Information "SplatParams: $($getKPNLisaPersonasSplatParams | ConvertTo-Json)"

    # Add header after printing splat
    $getKPNLisaPersonasSplatParams['Headers'] = $headers

    $getKPNLisaPersonasResponse = $null
    $getKPNLisaPersonasResponse = Invoke-RestMethod @getKPNLisaPersonasSplatParams
    $kpnLisaPersonas = $getKPNLisaPersonasResponse

    Write-Information "Queried personas. Result count: $(($kpnLisaPersonas | Measure-Object).Count)"
    #endregion Get Personas

    #region Get Personamembers
    # API docs: https://mwpapi.kpnwerkplek.com/index.html, specific API call: GET /api/personas/{identifier}/members
    $actionMessage = "querying Kpn Lisa Persona Members"
    foreach ($kpnLisaPersona in $kpnLisaPersonas) {  
        $kpnLisaPersonaMembers = [System.Collections.ArrayList]@()

        $getKPNLisaPersonaMembersSplatParams = @{
            Uri         = "$($actionContext.Configuration.MWPApiBaseUrl)/personas/$($kpnLisaPersona.id)/members"
            Method      = "GET"
            Verbose     = $false
            ErrorAction = "Stop"
        }

        Write-Information "SplatParams: $($getKPNLisaPersonaMembersSplatParams | ConvertTo-Json)"

        # Add header after printing splat
        $getKPNLisaPersonaMembersSplatParams['Headers'] = $headers

        $getKPNLisaPersonaMembersResponse = $null
        $getKPNLisaPersonaMembersResponse = Invoke-RestMethod @getKPNLisaPersonaMembersSplatParams

        if ($getKPNLisaPersonaMembersResponse -is [array]) {
            [void]$kpnLisaPersonaMembers.AddRange($getKPNLisaPersonaMembersResponse)
        }
        else {
            [void]$kpnLisaPersonaMembers.Add($getKPNLisaPersonaMembersResponse)
        }
        $numberOfAccounts = $(($kpnLisaPersonaMembers | Measure-Object).Count)

        # Make sure the displayname has a value of max 100 char
        if (-not([string]::IsNullOrEmpty($kpnLisaPersona.displayName))) {
            $displayname = $($kpnLisaPersona.displayName).substring(0, [System.Math]::Min(100, $($kpnLisaPersona.displayName).Length))
        }
        else {
            $displayname = $kpnLisaPersona.id
        }
        # Make sure the description has a value of max 100 char
        if (-not([string]::IsNullOrEmpty($kpnLisaPersona.description))) {
            $description = $($kpnLisaPersona.description).substring(0, [System.Math]::Min(100, $($kpnLisaPersona.description).Length))
        }
        else {
            $description = $null
        }

        $permission = @{
            PermissionReference = @{
                Id = $kpnLisaPersona.id
            }       
            Description         = $description
            DisplayName         = $displayName
        }

        # Batch permissions based on the amount of account references, 
        # to make sure the output objects are not above the limit
        $accountsBatchSize = 500
        if ($numberOfAccounts -gt 0) {
            $accountsBatchSize = 500
            $batches = 0..($numberOfAccounts - 1) | Group-Object { [math]::Floor($_ / $accountsBatchSize ) }
            foreach ($batch in $batches) {
                $permission.AccountReferences = [array]($batch.Group | ForEach-Object {
                    if($kpnLisaPersonaMembers[$_].objectId -eq '614d643b-d5ca-409c-9e12-954bb17eea6e'){
                        @($kpnLisaPersonaMembers[$_])
                    }
                    if($kpnLisaPersonaMembers[$_].objectId -eq '06032afa-e378-4def-9c56-4e4276707399'){
                        @($kpnLisaPersonaMembers[$_])
                    }
                    @($kpnLisaPersonaMembers[$_].objectId)
                 })
                Write-Output $permission
            }
        }
    }
    Write-Information 'Target permission import for [KPN Lisa Personas] completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-KPNLisaError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    # Required to write an error as uniqueness check doesn't show auditlog
    Write-Error $auditMessage
}