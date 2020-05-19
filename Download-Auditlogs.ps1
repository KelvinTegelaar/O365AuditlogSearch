##########################################
$ApplicationId         = 'xxxx-xxxx-xxx-xxxx-xxxx'
$ApplicationSecret     = 'TheSecretTheSecrey' | Convertto-SecureString -AsPlainText -Force
$TenantID              = 'YourTenantID'
$RefreshToken          = 'RefreshToken'
$ExchangeRefreshToken  = 'ExchangeRefreshToken'
$upn                   = 'UPN-Used-To-Generate-Tokens'
##########################################
$credential = New-Object System.Management.Automation.PSCredential($ApplicationId, $ApplicationSecret)
$aadGraphToken = New-PartnerAccessToken -ApplicationId $ApplicationId -Credential $credential -RefreshToken $refreshToken -Scopes 'https://graph.windows.net/.default' -ServicePrincipal -Tenant $tenantID
$graphToken = New-PartnerAccessToken -ApplicationId $ApplicationId -Credential $credential -RefreshToken $refreshToken -Scopes 'https://graph.microsoft.com/.default' -ServicePrincipal -Tenant $tenantID
Connect-MsolService -AdGraphAccessToken $aadGraphToken.AccessToken -MsGraphAccessToken $graphToken.AccessToken
 
$customers = Get-MsolPartnerContract -All
#Logged in. Moving on to creating folders and getting data.
$folderName = (Get-Date).tostring("dd-MM-yyyy")
$outputfolder = "C:\ScriptOutput"
new-item -Path $outputfolder -ItemType Directory -Name $folderName -Force
foreach ($customer in $customers) {
  $token = New-PartnerAccessToken -ApplicationId 'a0c73c16-a7e3-4564-9a95-2bdf47383716'-RefreshToken $ExchangeRefreshToken -Scopes 'https://outlook.office365.com/.default' -Tenant $customer.TenantId
  $tokenValue = ConvertTo-SecureString "Bearer $($token.AccessToken)" -AsPlainText -Force
  $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
  $customerId = $customer.DefaultDomainName
  $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($customerId)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection
  Import-PSSession $session -allowclobber -DisableNameChecking
 
  $startDate = (Get-Date).AddDays(-1)
  $endDate = (Get-Date)
  $Logs = @()
  Write-Host "Retrieving logs for $($customer.name)" -ForegroundColor Blue
  do {
    $logs += Search-unifiedAuditLog -SessionCommand ReturnLargeSet -SessionId $customer.name -ResultSize 5000 -StartDate $startDate -EndDate $endDate
    Write-Host "Retrieved $($logs.count) logs" -ForegroundColor Yellow
  }while ($Logs.count % 5000 -eq 0 -and $logs.count -ne 0)
  Write-Host "Finished Retrieving logs" -ForegroundColor Green
  $ObjLogs = foreach ($Log in $Logs) {
    $log.auditdata | convertfrom-json
  }
  $PreContent = @"
<H1> $($Customer.Name) - Audit Log from $StartDate until $EndDate </H1><br>
 
<br> Please note that this log is not complete - It is a representation where fields have been selected that are most commonly filtered on. .<br>
To analyze the complete log for this day, please click here for the complete CSV file log: <a href="$($Customer.Name).csv"/>CSV Logbook</a>
<br/>
<br/>
 
<input type="text" id="myInput" onkeyup="myFunction()" placeholder="Search...">
"@
  $head = @"
<script>
function myFunction() {
    const filter = document.querySelector('#myInput').value.toUpperCase();
    const trs = document.querySelectorAll('table tr:not(.header)');
    trs.forEach(tr => tr.style.display = [...tr.children].find(td => td.innerHTML.toUpperCase().includes(filter)) ? '' : 'none');
  }</script>
<Title>Audit Log Report</Title>
<style>
body { background-color:#E5E4E2;
      font-family:Monospace;
      font-size:10pt; }
td, th { border:0px solid black; 
        border-collapse:collapse;
        white-space:pre; }
th { color:white;
    background-color:black; }
table, tr, td, th {
     padding: 2px; 
     margin: 0px;
     white-space:pre; }
tr:nth-child(odd) {background-color: lightgray}
table { width:95%;margin-left:5px; margin-bottom:20px; }
h2 {
font-family:Tahoma;
color:#6D7B8D;
}
.footer 
{ color:green; 
 margin-left:10px; 
 font-family:Tahoma;
 font-size:8pt;
 font-style:italic;
}
#myInput {
  background-image: url('https://www.w3schools.com/css/searchicon.png'); /* Add a search icon to input */
  background-position: 10px 12px; /* Position the search icon */
  background-repeat: no-repeat; /* Do not repeat the icon image */
  width: 50%; /* Full-width */
  font-size: 16px; /* Increase font-size */
  padding: 12px 20px 12px 40px; /* Add some padding */
  border: 1px solid #ddd; /* Add a grey border */
  margin-bottom: 12px; /* Add some space below the input */
}
</style>
"@
  #$ObjLogs
  $Logs | export-csv "$($outputfolder)\$($FolderName)\$($Customer.Name).csv" -NoTypeInformation
  $ObjLogs | Select-object CreationTime, UserID, Operation, ResultStatus, ClientIP, Workload, ClientInfoString, * -ErrorAction SilentlyContinue | Convertto-html -head $head -PreContent $PreContent | out-file "$($outputfolder)\$($FolderName)\$($customer.Name).html"
}