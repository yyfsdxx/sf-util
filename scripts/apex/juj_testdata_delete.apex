// =====================================================================
// 従事事業応募（JUJ080／081／082）単体テスト用データ 削除スクリプト
// 実行：sf apex run --file scripts/apex/juj_testdata_delete.apex --target-org <alias>
// 対象：下記のキーに完全一致するデータ、およびそのテスト用従事事業の応募（テストで登録した応募を含む）
// =====================================================================

// ---------- テストデータのキー（固定値）----------
// ※ 前方一致（LIKE）は使わず、以下の値に完全一致するデータだけを登録・削除・確認する
// ※ org の既存データと重複する場合はここを変更する。insert・reset・delete・check の4本とも同じ値にすること
String NENDO = '2026';
List<String> JIGYO_NOS = new List<String>{ '9990001', '9990002', '9990003', '9990004', '9990005', '9990006', '9990007', '9990008' }; // 事業 A〜H
List<String> KAIIN_NOS = new List<String>{ 'T100001', 'T100002', 'T100003', 'T100004' }; // 会員の登録番号
List<String> SODANIN_NOS = new List<String>{ 'T900001', 'T900002' }; // 相談員番号
List<String> BASYO_NOS = new List<String>{ 'T000000001', 'T000000002' }; // 従事場所No.
List<String> SIBU_CODES = new List<String>{ 'T01', 'T02' }; // 事務所・法人の支部コード
List<String> ACCOUNT_NAMES = new List<String>{ 'テスト東事務所', 'テスト西事務所' }; // 事務所・法人名

List<Juji_Jigyo__c> jigyos = [
    SELECT Id, Juji_Juji_Jigyo_No__c, Juji_Juji_Jigyo_Name__c FROM Juji_Jigyo__c
    WHERE Juji_Juji_Jigyo_No__c IN :JIGYO_NOS AND Juji_Jisi_Nendo__c = :NENDO
];
List<Juji_Jigyo_Oubo__c> oubos = [SELECT Id FROM Juji_Jigyo_Oubo__c WHERE Oubo_Juji_Jigyo__c IN :jigyos];
List<Contact> members = [SELECT Id, Kaii_Toroku_No__c, Name FROM Contact WHERE Kaii_Toroku_No__c IN :KAIIN_NOS];
List<Soudanin_Master__c> sodanins = [SELECT Id, SouM_Sodanin_No__c, SouM_Sodanin_Name__c FROM Soudanin_Master__c WHERE SouM_Sodanin_No__c IN :SODANIN_NOS];
List<Juji_Basyo_Master__c> basyos = [SELECT Id, JujM_Juji_Basyo_No__c, JujM_Juji_Basyo_Name__c FROM Juji_Basyo_Master__c WHERE JujM_Juji_Basyo_No__c IN :BASYO_NOS];
List<Account> accounts = [SELECT Id, Name FROM Account WHERE Name IN :ACCOUNT_NAMES AND Jims_Sibu_Code__c IN :SIBU_CODES];

// 応募（応募明細は主従で連動削除）→ 従事事業（明細・割当・応募明細は主従で連動削除）→ 会員・相談員 → 従事場所マスタ → 事務所・法人
delete oubos;
delete jigyos;
delete members;
delete sodanins;
delete basyos;
delete accounts;

System.debug(LoggingLevel.ERROR, '削除完了：応募 ' + oubos.size() + '、従事事業 ' + jigyos.size() + '、会員 ' + members.size()
    + '、相談員 ' + sodanins.size() + '、従事場所マスタ ' + basyos.size() + '、事務所・法人 ' + accounts.size());
