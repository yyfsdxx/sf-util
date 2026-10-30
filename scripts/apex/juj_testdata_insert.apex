// =====================================================================
// 従事事業応募（JUJ080／081／082）単体テスト用データ 登録スクリプト
// 内容：`20 単体テスト データ（作業用）` の 34件（時間帯1件版・JSON 版とも）
// 実行：sf apex run --file scripts/apex/juj_testdata_insert.apex --target-org <alias>
// ※ 登録のみ行う。キーが一致するデータが既にある場合はエラーで中断する（作り直す場合は juj_testdata_reset.apex）
// ※ エラーの場合はすべて取り消される（エラーメッセージに対象の項目・入力規則が表示される）
// =====================================================================

// 時間帯1件版（応募明細・割当を1件＝1時間帯で登録）の場合は true
Boolean SLOT_VERSION = false;

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

// ---------- 既存データの確認（キーが一致するデータがある場合は登録しない）----------
List<Juji_Jigyo__c> jigyos = [
    SELECT Id, Juji_Juji_Jigyo_No__c, Juji_Juji_Jigyo_Name__c FROM Juji_Jigyo__c
    WHERE Juji_Juji_Jigyo_No__c IN :JIGYO_NOS AND Juji_Jisi_Nendo__c = :NENDO
];
List<Juji_Jigyo_Oubo__c> oubos = [SELECT Id FROM Juji_Jigyo_Oubo__c WHERE Oubo_Juji_Jigyo__c IN :jigyos];
List<Contact> members = [SELECT Id, Kaii_Toroku_No__c, Name FROM Contact WHERE Kaii_Toroku_No__c IN :KAIIN_NOS];
List<Soudanin_Master__c> sodanins = [SELECT Id, SouM_Sodanin_No__c, SouM_Sodanin_Name__c FROM Soudanin_Master__c WHERE SouM_Sodanin_No__c IN :SODANIN_NOS];
List<Juji_Basyo_Master__c> basyos = [SELECT Id, JujM_Juji_Basyo_No__c, JujM_Juji_Basyo_Name__c FROM Juji_Basyo_Master__c WHERE JujM_Juji_Basyo_No__c IN :BASYO_NOS];
List<Account> accounts = [SELECT Id, Name FROM Account WHERE Name IN :ACCOUNT_NAMES AND Jims_Sibu_Code__c IN :SIBU_CODES];
List<String> existing = new List<String>();
for (Juji_Jigyo__c r : jigyos) existing.add('従事事業 ' + r.Juji_Juji_Jigyo_No__c + '（' + r.Juji_Juji_Jigyo_Name__c + '）');
for (Contact r : members) existing.add('会員 ' + r.Kaii_Toroku_No__c + '（' + r.Name + '）');
for (Soudanin_Master__c r : sodanins) existing.add('相談員 ' + r.SouM_Sodanin_No__c + '（' + r.SouM_Sodanin_Name__c + '）');
for (Juji_Basyo_Master__c r : basyos) existing.add('従事場所 ' + r.JujM_Juji_Basyo_No__c + '（' + r.JujM_Juji_Basyo_Name__c + '）');
for (Account r : accounts) existing.add('事務所・法人 ' + r.Name);
if (!existing.isEmpty()) {
    throw new IllegalArgumentException('キーが一致するデータが既にあります：' + String.join(existing, '、')
        + '。テストデータの場合は juj_testdata_reset.apex（作り直し）または juj_testdata_delete.apex（削除）を、'
        + '他のデータと重複している場合は各スクリプトのキーを変更してください。');
}

// ---------- 1. Account（事務所・法人）----------
Account acc1 = new Account(Name = ACCOUNT_NAMES[0], Jims_Sibu_Code__c = SIBU_CODES[0], Jims_Sibu_Name__c = 'テスト東支部');
Account acc2 = new Account(Name = ACCOUNT_NAMES[1], Jims_Sibu_Code__c = SIBU_CODES[1], Jims_Sibu_Name__c = 'テスト西支部');
insert new List<Account>{ acc1, acc2 };

// ---------- 2. 従事場所マスタ（支部コードは従事事業の事務所・法人と同じにする：入力規則）----------
Juji_Basyo_Master__c bs1 = new Juji_Basyo_Master__c(
    JujM_Juji_Basyo_No__c = BASYO_NOS[0], JujM_Juji_Basyo_Name__c = 'テスト会場', JujM_Sibu_Code__c = SIBU_CODES[0]);
Juji_Basyo_Master__c bs2 = new Juji_Basyo_Master__c(
    JujM_Juji_Basyo_No__c = BASYO_NOS[1], JujM_Juji_Basyo_Name__c = 'テスト西会場', JujM_Sibu_Code__c = SIBU_CODES[1]);
insert new List<Juji_Basyo_Master__c>{ bs1, bs2 };

// ---------- 3. 従事事業 ----------
// 入力規則（11 の従事事業 入力規則一覧）：謝金支払方法・交通費支払方法・インターネット募集区分は必須
//   謝金無以外：謝金額・謝金単位区分・謝金額内税外税・支払調書区分（謝金）も必須
//   交通費無：交通費の条件付き必須（交通費額・課税区分・内税外税・支払調書区分）は対象外
//   インターネット募集期間（From≦To）・募集対象は、募集区分の値によらず入力規則を満たす値を設定する
Map<String, Juji_Jigyo__c> jigyo = new Map<String, Juji_Jigyo__c>();
List<List<String>> jigyoDefs = new List<List<String>>{
    // 記号, 従事事業No., 従事事業名, 謝金支払方法
    new List<String>{ 'A', JIGYO_NOS[0], 'テスト事業A（基本）', '謝金無' },
    new List<String>{ 'B', JIGYO_NOS[1], 'テスト事業B（実施日なし）', '謝金無' },
    new List<String>{ 'C', JIGYO_NOS[2], 'テスト事業C（必須多）', '謝金無' },
    new List<String>{ 'D', JIGYO_NOS[3], 'テスト事業D（可能日必須）', '謝金無' },
    new List<String>{ 'E', JIGYO_NOS[4], 'テスト事業E（スキル不可）', '謝金無' },
    new List<String>{ 'F', JIGYO_NOS[5], 'テスト事業F（他支部）', '謝金無' },
    new List<String>{ 'G', JIGYO_NOS[6], 'テスト事業G（未採番のみ）', '現金' },
    new List<String>{ 'H', JIGYO_NOS[7], 'テスト事業H（全削除用）', '現金' }
};
for (List<String> d : jigyoDefs) {
    Boolean isF = d[0] == 'F';
    Juji_Jigyo__c j = new Juji_Jigyo__c(
        Juji_Juji_Jigyo_No__c = d[1],
        Juji_Jisi_Nendo__c = NENDO,
        Juji_Juji_Jigyo_Name__c = d[2],
        Juji_Jimusyo_Hojin__c = isF ? acc2.Id : acc1.Id,
        Juji_Juji_Basyo_Master__c = isF ? bs2.Id : bs1.Id,
        Juji_Syakin_Siharai_Hoho__c = d[3],
        Juji_Kotuhi_Siharai_Hoho__c = '交通費無',
        Juji_Internet_Bosyu_Kubun__c = '募集する',
        Juji_Internet_Bosyu_Kikan_From__c = Date.newInstance(2026, 10, 1),
        Juji_Internet_Bosyu_Kikan_To__c = Date.newInstance(2026, 12, 31),
        Juji_Internet_Bosyu_Taisyo__c = '限定無し'
    );
    if (d[3] != '謝金無') {
        j.Juji_Syakingaku__c = 10000;
        j.Juji_Syakin_Tani_Kubun__c = '日数単位';
        j.Juji_Syakingaku_Utizei_Sotozei__c = '外税';
        j.Juji_Siharai_Tyosyo_Kubun_Syakin__c = '相談謝金';
    }
    jigyo.put(d[0], j);
}
// 入力フラグ（事業C・D・E）
jigyo.get('C').Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Yobi__c = '必須';
jigyo.get('C').Juji_Ouboji_Hisu_Nyuryoku_Flag_Kibo_Nisu__c = '必須';
jigyo.get('C').Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c = '必須';
jigyo.get('C').Juji_Ouboji_Nini_Nyuryoku_Flag_Skill_Tok__c = '禁止';
jigyo.get('C').Juji_Ouboji_Nini_Nyuryoku_Flag_Tyosyo__c = '禁止';
jigyo.get('C').Juji_Ouboji_Nini_Nyuryoku_Flag_Sodan__c = '禁止';
jigyo.get('D').Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Hi__c = '必須';
jigyo.get('E').Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c = '省略可';
jigyo.get('E').Juji_Ouboji_Nini_Nyuryoku_Flag_5Dankai__c = '禁止';
insert jigyo.values();

// ---------- 4. 従事事業明細（実施日）----------
// 記号, 事業, 実施日, 募集人数, 開始, 終了, 備考, 実施時間帯明細（JSON）
List<List<String>> meisaiDefs = new List<List<String>>{
    new List<String>{ 'JM1', 'A', '2026-11-03', '5', '09:00', '15:00', '午前・午後',
        '[{"startTime":"09:00","endTime":"12:00","count":3},{"startTime":"13:00","endTime":"15:00","count":2}]' },
    new List<String>{ 'JM2', 'A', '2026-11-10', '1', '10:00', '11:00', '', '[{"startTime":"10:00","endTime":"11:00","count":1}]' },
    new List<String>{ 'JM3', 'A', '2026-12-01', '2', '10:00', '11:00', '', '[{"startTime":"10:00","endTime":"11:00","count":2}]' },
    new List<String>{ 'JM4', 'C', '2026-11-03', '2', '09:00', '12:00', '', '[{"startTime":"09:00","endTime":"12:00","count":2}]' },
    new List<String>{ 'JM5', 'D', '2026-11-03', '2', '09:00', '12:00', '', '[{"startTime":"09:00","endTime":"12:00","count":2}]' }
};
List<Juji_Jigyo_Meisai__c> meisais = new List<Juji_Jigyo_Meisai__c>();
for (List<String> d : meisaiDefs) {
    meisais.add(new Juji_Jigyo_Meisai__c(
        Juji_Meisai_Juji_Jigyo__c = jigyo.get(d[1]).Id,
        Juji_Meisai_Jisi_Nengapi__c = Date.valueOf(d[2]),
        Juji_Meisai_Bosyu_Ninzu__c = Integer.valueOf(d[3]),
        Juji_Meisai_Kaisi_Jikoku__c = toTime(d[4]),
        Juji_Meisai_Syuryo_Jikoku__c = toTime(d[5]),
        Juji_Meisai_Biko__c = String.isBlank(d[6]) ? null : d[6],
        Juji_Meisai_JisshiJikantai_Meisai__c = d[7]
    ));
}
insert meisais;

// ---------- 5. 会員（Contact）※ レコードタイプがある場合は会員用を設定すること ----------
Contact m1 = new Contact(Kaii_Toroku_No__c = KAIIN_NOS[0], LastName = 'テスト 一郎', AccountId = acc1.Id,
    Kaii_Kaiin_Name_Furigana_Sei__c = 'テスト', Kaii_Kaiin_Name_Furigana_Mei__c = 'イチロウ',
    Kaii_Jimusyo_Syozaiti__c = '東京都千代田区1-1-1', Kaii_Jimusyo_Tel_No__c = '03-0000-0001', Kaii_Jimusyo_Fax_No__c = '03-0000-1001');
Contact m2 = new Contact(Kaii_Toroku_No__c = KAIIN_NOS[1], LastName = 'テスト 二郎', AccountId = acc2.Id,
    Kaii_Kaiin_Name_Furigana_Sei__c = 'テスト', Kaii_Kaiin_Name_Furigana_Mei__c = 'ジロウ',
    Kaii_Jimusyo_Syozaiti__c = '東京都港区2-2-2', Kaii_Jimusyo_Tel_No__c = '03-0000-0002', Kaii_Jimusyo_Fax_No__c = '03-0000-1002');
Contact m3 = new Contact(Kaii_Toroku_No__c = KAIIN_NOS[2], LastName = 'テスト 三郎', AccountId = acc1.Id,
    Kaii_Kaiin_Name_Furigana_Sei__c = 'テスト', Kaii_Kaiin_Name_Furigana_Mei__c = 'サブロウ',
    Kaii_Jimusyo_Syozaiti__c = '東京都新宿区3-3-3', Kaii_Jimusyo_Tel_No__c = '03-0000-0003', Kaii_Jimusyo_Fax_No__c = '03-0000-1003');
// 氏名33文字以上（応募.氏名の32文字切捨て確認用）
Contact m4 = new Contact(Kaii_Toroku_No__c = KAIIN_NOS[3], LastName = 'テスト長氏名'.repeat(6), AccountId = acc1.Id,
    Kaii_Kaiin_Name_Furigana_Sei__c = 'テスト', Kaii_Kaiin_Name_Furigana_Mei__c = 'シロウ');
Database.DMLOptions allowDup = new Database.DMLOptions();
allowDup.DuplicateRuleHeader.allowSave = true; // 重複ルールの警告を無視して登録する
allowDup.OptAllOrNone = true;
Database.insert(new List<Contact>{ m1, m2, m3, m4 }, allowDup);

// ---------- 6. 相談員マスタ ----------
Soudanin_Master__c s1 = new Soudanin_Master__c(SouM_Sodanin_No__c = SODANIN_NOS[0], SouM_Sodanin_Name__c = 'テスト 花子',
    SouM_Sodanin_Name_Furigana__c = 'テスト ハナコ', SouM_Jimusyo_Jusyo__c = '京都府京都市1-1-1', SouM_Jimusyo_Tel_No__c = '075-000-0001');
Soudanin_Master__c s2 = new Soudanin_Master__c(SouM_Sodanin_No__c = SODANIN_NOS[1], SouM_Sodanin_Name__c = 'テスト 一郎相談',
    SouM_Sodanin_Name_Furigana__c = 'テスト イチロウソウダン', SouM_Jimusyo_Jusyo__c = '京都府京都市2-2-2',
    SouM_Jimusyo_Tel_No__c = '075-000-0002', SouM_Jimusyo_Fax_No__c = '075-000-1002');
Database.insert(new List<Soudanin_Master__c>{ s1, s2 }, allowDup);

// ---------- 7. 従事事業応募 ----------
Juji_Jigyo_Oubo__c ob1 = newOubo(jigyo.get('A').Id, m2.Id, null, 1, m2.LastName, 'Mon,Wed');
ob1.Oubo_Renrakusaki_Mail__c = 'test@example.com';
ob1.Oubo_Biko__c = '備考テスト';
ob1.Oubo_Skill_Syotoku_Zei__c = '5';
Juji_Jigyo_Oubo__c ob2 = newOubo(jigyo.get('A').Id, m3.Id, null, 2, m3.LastName, 'Tue');
Juji_Jigyo_Oubo__c ob3 = newOubo(jigyo.get('A').Id, null, s2.Id, 3, s2.SouM_Sodanin_Name__c, '');
Juji_Jigyo_Oubo__c ob4 = newOubo(jigyo.get('A').Id, null, s1.Id, 0, s1.SouM_Sodanin_Name__c, ''); // マイページからの応募
Juji_Jigyo_Oubo__c ob5 = newOubo(jigyo.get('G').Id, m1.Id, null, 0, m1.LastName, '');
Juji_Jigyo_Oubo__c ob6 = newOubo(jigyo.get('H').Id, m1.Id, null, 1, m1.LastName, '');
Juji_Jigyo_Oubo__c ob7 = newOubo(jigyo.get('H').Id, m3.Id, null, 2, m3.LastName, '');
insert new List<Juji_Jigyo_Oubo__c>{ ob1, ob2, ob3, ob4, ob5, ob6, ob7 };

// ---------- 8. 従事事業応募明細 ----------
List<Juji_Jigyo_Oubo_Meisai__c> obMeisais = new List<Juji_Jigyo_Oubo_Meisai__c>();
if (SLOT_VERSION) {
    // 時間帯1件版：OM1 のみ（11/03 13:00-15:00）。時間帯なしの明細（OM2）は存在しない
    obMeisais.add(newOuboMeisai(ob1.Id, jigyo.get('A').Id, '2026-11-03', '13:00', '15:00', null));
} else {
    obMeisais.add(newOuboMeisai(ob1.Id, jigyo.get('A').Id, '2026-11-03', null, null, '[{"startTime":"13:00","endTime":"15:00"}]'));
    obMeisais.add(newOuboMeisai(ob6.Id, jigyo.get('H').Id, '2026-11-10', null, null, null)); // 時間帯なしの日付
}
insert obMeisais;

// ---------- 9. 従事事業割当（割当フラグ・確定フラグの値は 0／1）----------
List<Juji_Jigyo_Wariate__c> wariates = new List<Juji_Jigyo_Wariate__c>();
if (SLOT_VERSION) {
    wariates.add(newWariate(jigyo.get('A').Id, m3.Id, null, '2026-11-10', '1', '0', '10:00', '11:00', null)); // WR1 仮割当
    wariates.add(newWariate(jigyo.get('A').Id, null, s2.Id, '2026-11-03', '0', '1', '09:00', '12:00', null)); // WR2 確定
    wariates.add(newWariate(jigyo.get('A').Id, null, s2.Id, '2026-11-03', '0', '1', '13:00', '15:00', null)); // WR2 確定
} else {
    wariates.add(newWariate(jigyo.get('A').Id, m3.Id, null, '2026-11-10', '1', '0', null, null,
        '[{"startTime":"10:00","endTime":"11:00"}]'));
    wariates.add(newWariate(jigyo.get('A').Id, null, s2.Id, '2026-11-03', '0', '1', null, null,
        '[{"startTime":"09:00","endTime":"12:00"},{"startTime":"13:00","endTime":"15:00"}]'));
}
insert wariates;

System.debug(LoggingLevel.ERROR, '登録完了（' + (SLOT_VERSION ? '時間帯1件版' : 'JSON 版') + '）：Account 2、従事場所マスタ 2、従事事業 ' + jigyo.size()
    + '、従事事業明細 ' + meisais.size() + '、会員 4、相談員 2、応募 7、応募明細 ' + obMeisais.size() + '、割当 ' + wariates.size());

// ==================== ヘルパー ====================
// 'HH:mm' → Time
Time toTime(String hhmm) {
    if (String.isBlank(hhmm)) {
        return null;
    }
    List<String> parts = hhmm.split(':');
    return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 0, 0);
}

// 従事事業応募。yobi は「可」とする曜日（Sun,Mon,…をカンマ区切り）。それ以外の曜日は「不可」
Juji_Jigyo_Oubo__c newOubo(Id jigyoId, Id kaiinId, Id sodaninId, Integer uketukeNo, String name, String yobi) {
    Set<String> kano = new Set<String>(String.isBlank(yobi) ? new List<String>() : yobi.split(','));
    Juji_Jigyo_Oubo__c o = new Juji_Jigyo_Oubo__c(
        Oubo_Juji_Jigyo__c = jigyoId,
        Oubo_Kaiin__c = kaiinId,
        Oubo_Soudanin_Master__c = sodaninId,
        Oubo_Uketuke_No__c = uketukeNo,
        Oubo_Shimei__c = name.left(32),
        Oubo_Juji_Keiken__c = '有'
    );
    for (String day : new List<String>{ 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }) {
        o.put('Oubo_Juji_Kano_Yobi_Flag_' + day + '__c', kano.contains(day) ? '可' : '不可');
    }
    return o;
}

// 従事事業応募明細。版により異なる項目は put で設定する（存在しない項目を参照してコンパイルエラーにならないように）
Juji_Jigyo_Oubo_Meisai__c newOuboMeisai(Id ouboId, Id jigyoId, String kanoDate, String startTime, String endTime, String jsonText) {
    Juji_Jigyo_Oubo_Meisai__c m = new Juji_Jigyo_Oubo_Meisai__c();
    m.put('Oubo_Meisa_Juji_Jigyo_Oubo__c', ouboId);
    m.put('Oubo_Meisa_Juji_Jigyo__c', jigyoId);
    m.put('Oubo_Meisa_Juji_Kano_Nengapi__c', Date.valueOf(kanoDate));
    if (startTime != null) {
        m.put('Oubo_Meisai_Kaisi_Jikoku__c', toTime(startTime));
        m.put('Oubo_Meisai_Syuryo_Jikoku__c', toTime(endTime));
    }
    if (jsonText != null) {
        m.put('Oubo_Meisa_JisshiJikantai_Meisai__c', jsonText);
    }
    return m;
}

// 従事事業割当
Juji_Jigyo_Wariate__c newWariate(Id jigyoId, Id kaiinId, Id sodaninId, String jujiDate, String wariateFlag,
    String kakuteiFlag, String startTime, String endTime, String jsonText) {
    Juji_Jigyo_Wariate__c w = new Juji_Jigyo_Wariate__c(
        Wari_Juji_Jigyo__c = jigyoId,
        Wari_Kaiin__c = kaiinId,
        Wari_Soudanin_Master__c = sodaninId,
        Wari_Juji_Nengapi__c = Date.valueOf(jujiDate),
        Wari_Wriate_Flag__c = wariateFlag,
        Wari_Kakutei_Flag__c = kakuteiFlag
    );
    if (startTime != null) {
        w.put('Wari_Kaisi_Jikoku__c', toTime(startTime));
        w.put('Wari_Syuryo_Jikoku__c', toTime(endTime));
    }
    if (jsonText != null) {
        w.put('Wari_JisshiJikantai_Meisai__c', jsonText);
    }
    return w;
}
