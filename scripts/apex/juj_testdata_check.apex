// =====================================================================
// 従事事業応募（JUJ080／081／082）単体テスト用データ 件数確認スクリプト
// 実行：sf apex run --file scripts/apex/juj_testdata_check.apex --target-org <alias>
// 期待値：どちらの版も 34件（JSON 版 応募明細 2・割当 2／時間帯1件版 応募明細 1・割当 3）
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
Integer meisai = [SELECT COUNT() FROM Juji_Jigyo_Meisai__c WHERE Juji_Meisai_Juji_Jigyo__c IN :jigyos];
Integer ouboMeisai = [SELECT COUNT() FROM Juji_Jigyo_Oubo_Meisai__c WHERE Oubo_Meisa_Juji_Jigyo__c IN :jigyos];
Integer wariate = [SELECT COUNT() FROM Juji_Jigyo_Wariate__c WHERE Wari_Juji_Jigyo__c IN :jigyos];

System.debug(LoggingLevel.ERROR, '件数：Account ' + accounts.size() + '（2）、従事場所マスタ ' + basyos.size() + '（2）、従事事業 ' + jigyos.size()
    + '（8）、従事事業明細 ' + meisai + '（5）、会員 ' + members.size() + '（4）、相談員 ' + sodanins.size() + '（2）、応募 ' + oubos.size()
    + '（7）、応募明細 ' + ouboMeisai + '（JSON 版 2／時間帯1件版 1）、割当 ' + wariate + '（JSON 版 2／時間帯1件版 3）');

// 081 の割当人数の確認用（事業A の割当の一覧）
String jigyoNoA = JIGYO_NOS[0];
for (Juji_Jigyo_Wariate__c w : [
    SELECT Wari_Juji_Nengapi__c, Wari_Wriate_Flag__c, Wari_Kakutei_Flag__c, Wari_Kaiin__c, Wari_Kaiin__r.Kaii_Toroku_No__c,
        Wari_Soudanin_Master__r.SouM_Sodanin_No__c
    FROM Juji_Jigyo_Wariate__c
    WHERE Wari_Juji_Jigyo__r.Juji_Juji_Jigyo_No__c = :jigyoNoA AND Wari_Juji_Jigyo__r.Juji_Jisi_Nendo__c = :NENDO
    ORDER BY Wari_Juji_Nengapi__c
]) {
    System.debug(LoggingLevel.ERROR, '割当：' + w.Wari_Juji_Nengapi__c + ' 割当=' + w.Wari_Wriate_Flag__c + ' 確定=' + w.Wari_Kakutei_Flag__c
        + ' 従事者=' + (w.Wari_Kaiin__c != null ? w.Wari_Kaiin__r.Kaii_Toroku_No__c : w.Wari_Soudanin_Master__r.SouM_Sodanin_No__c));
}
