/**
 * Juj_JigyoOboTourokuController のテストクラス
 * ※ コントローラの戻り値は Map のため、ヘルパーで値を取り出して検証する。
 */
@IsTest
private class Juj_JigyoOboTourokuControllerTest {

    private static final String JIGYO_NO = '0000001';
    private static final String BASYO_NO = '0000000001';
    private static final String NENDO = '2026';
    private static final String WRONG_JIGYO_NO = '9999999';
    private static final String MEMBER_NO = '1234567';
    private static final String SODANIN_NO = '7654321';

    @TestSetup
    static void setup() {
        Account shibu = new Account(Name = 'テスト事務局', Jims_Sibu_Code__c = '001', Jims_Sibu_Name__c = 'テスト支部');
        insert shibu;
        Juji_Basyo_Master__c basyo = new Juji_Basyo_Master__c(
            JujM_Juji_Basyo_No__c = BASYO_NO,
            JujM_Juji_Basyo_Name__c = 'テスト場所',
            // 従事事業の入力規則：従事事業の事務所・法人と同じ支部コード
            JujM_Sibu_Code__c = '001'
        );
        insert basyo;
        insert new Juji_Jigyo__c(
            Juji_Juji_Jigyo_No__c = JIGYO_NO,
            Juji_Juji_Basyo_Master__c = basyo.Id,
            Juji_Jisi_Nendo__c = NENDO,
            Juji_Juji_Jigyo_Name__c = 'テスト事業',
            // 従事事業の入力規則を満たす値
            Juji_Syakin_Siharai_Hoho__c = '謝金無',
            Juji_Kotuhi_Siharai_Hoho__c = '交通費無',
            Juji_Internet_Bosyu_Kubun__c = '募集する',
            Juji_Internet_Bosyu_Kikan_From__c = Date.today().addDays(-30),
            Juji_Internet_Bosyu_Kikan_To__c = Date.today().addDays(60),
            Juji_Internet_Bosyu_Taisyo__c = '限定無し',
            Juji_Jimusyo_Hojin__c = shibu.Id
        );
        // 会員が参照する事務所・法人（従事事業とは別の支部）
        Account office = new Account(Name = 'テスト税理士事務所', Jims_Sibu_Code__c = '002', Jims_Sibu_Name__c = '西支部');
        insert office;
        // Name はロケールにより姓名の順序が変わるため、姓のみに氏名全体を設定する
        insert new Contact(
            Kaii_Toroku_No__c = MEMBER_NO,
            LastName = 'テスト 太郎',
            Kaii_Kaiin_Name_Furigana_Sei__c = 'テスト',
            Kaii_Kaiin_Name_Furigana_Mei__c = 'タロウ',
            AccountId = office.Id,
            Kaii_Jimusyo_Syozaiti__c = '東京都千代田区1-1-1',
            Kaii_Jimusyo_Tel_No__c = '03-0000-0000',
            Kaii_Jimusyo_Fax_No__c = '03-0000-0001'
        );
        insert new Soudanin_Master__c(
            SouM_Sodanin_No__c = SODANIN_NO,
            SouM_Sodanin_Name__c = '相談 花子',
            SouM_Sodanin_Name_Furigana__c = 'ソウダン ハナコ'
        );
    }

    // ==================== ヘルパー ====================
    // Map の階層をたどって値を取得する（例：get(r, 'jigyo.jigyoName')）
    private static Object get(Map<String, Object> m, String path) {
        Object current = m;
        for (String key : path.split('\\.')) {
            if (current == null) {
                return null;
            }
            current = ((Map<String, Object>) current).get(key);
        }
        return current;
    }

    // 数値として取得する（JSON 経由のため Integer・Decimal のどちらにもなり得る）
    private static Decimal num(Map<String, Object> m, String path) {
        Object value = get(m, path);
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static Juj_JigyoOboTourokuController.JigyoKey key() {
        Juj_JigyoOboTourokuController.JigyoKey k = new Juj_JigyoOboTourokuController.JigyoKey();
        k.jujiJigyoNo = JIGYO_NO;
        k.jujiBasyoNo = BASYO_NO;
        k.jisiNendo = NENDO;
        return k;
    }

    private static Juj_JigyoOboTourokuController.ApplicationForm form() {
        Juj_JigyoOboTourokuController.ApplicationForm f = new Juj_JigyoOboTourokuController.ApplicationForm();
        f.telFixed = '03-1111-1111';
        f.mail = 'test@example.com';
        f.allDays = false;
        f.weekdays = new List<String>{ '月', '水' };
        f.kibouNissu = '3';
        f.keiken = '有';
        Juj_JigyoOboTourokuController.SkillValue skill = new Juj_JigyoOboTourokuController.SkillValue();
        skill.field = Juj_JigyoOboTourokuController.SKILL_FIELDS[0];
        skill.value = '5';
        f.skills = new List<Juj_JigyoOboTourokuController.SkillValue>{ skill };
        f.sodanKamoku = '所得税';
        return f;
    }

    private static Juj_JigyoOboTourokuController.SaveRequest addRequest(String jujishaNo) {
        Juj_JigyoOboTourokuController.SaveRequest req = new Juj_JigyoOboTourokuController.SaveRequest();
        req.jigyoKey = key();
        req.jujishaNo = jujishaNo;
        req.form = form();
        req.kanoubiDates = new List<Juj_JigyoOboTourokuController.KanoubiDate>{
            kanoubi('2026-11-01', '13:00', '15:00'),
            kanoubi('2026-11-08', '09:00', '12:00')
        };
        return req;
    }

    // 変更モードの登録リクエスト。システム更新日時・応募明細の版は、画面と同じく応募の読込結果から設定する
    private static Juj_JigyoOboTourokuController.SaveRequest changeRequest(Juji_Jigyo_Oubo__c app) {
        Map<String, Object> loaded = Juj_JigyoOboTourokuController.loadApplication(app.Id, null, null, null, null);
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(MEMBER_NO);
        req.applicationId = app.Id;
        req.systemModstamp = app.SystemModstamp;
        req.meisaiVersion = (String) get(loaded, 'application.meisaiVersion');
        return req;
    }

    // 応募の明細（従事可能日・開始時間の昇順）
    private static List<Juji_Jigyo_Oubo_Meisai__c> details(Id appId) {
        return [
            SELECT Id, Oubo_Meisa_Juji_Kano_Nengapi__c, Oubo_Meisai_Kaisi_Jikoku__c, Oubo_Meisai_Syuryo_Jikoku__c
            FROM Juji_Jigyo_Oubo_Meisai__c
            WHERE Oubo_Meisa_Juji_Jigyo_Oubo__c = :appId
            ORDER BY Oubo_Meisa_Juji_Kano_Nengapi__c, Oubo_Meisai_Kaisi_Jikoku__c
        ];
    }

    private static Juji_Jigyo_Oubo_Meisai__c newDetail(Id appId, Date kanoubiDate, Integer startHour, Integer endHour) {
        return new Juji_Jigyo_Oubo_Meisai__c(
            Oubo_Meisa_Juji_Jigyo_Oubo__c = appId,
            Oubo_Meisa_Juji_Jigyo__c = jigyo().Id,
            Oubo_Meisa_Juji_Kano_Nengapi__c = kanoubiDate,
            Oubo_Meisai_Kaisi_Jikoku__c = Time.newInstance(startHour, 0, 0, 0),
            Oubo_Meisai_Syuryo_Jikoku__c = Time.newInstance(endHour, 0, 0, 0)
        );
    }

    // 従事可能日（時間帯1件）
    private static Juj_JigyoOboTourokuController.KanoubiDate kanoubi(String kanoubiDate, String startTime, String endTime) {
        Juj_JigyoOboTourokuController.TimeSlot slot = new Juj_JigyoOboTourokuController.TimeSlot();
        slot.startTime = startTime;
        slot.endTime = endTime;
        Juj_JigyoOboTourokuController.KanoubiDate k = new Juj_JigyoOboTourokuController.KanoubiDate();
        k.kanoubiDate = kanoubiDate;
        k.timeSlots = new List<Juj_JigyoOboTourokuController.TimeSlot>{ slot };
        return k;
    }

    // 画面と同じく JSON 文字列で登録処理を呼び出す
    private static Map<String, Object> save(Juj_JigyoOboTourokuController.SaveRequest req) {
        return Juj_JigyoOboTourokuController.saveApplication(JSON.serialize(req));
    }

    private static Juji_Jigyo__c jigyo() {
        return [SELECT Id FROM Juji_Jigyo__c WHERE Juji_Juji_Jigyo_No__c = :JIGYO_NO LIMIT 1];
    }

    private static Contact member() {
        return [SELECT Id FROM Contact WHERE Kaii_Toroku_No__c = :MEMBER_NO LIMIT 1];
    }

    // 会員の応募を作成する（明細2件付き：11/01 の 13:00-15:00・09:00-12:00。順序は逆に登録する）
    private static Juji_Jigyo_Oubo__c createMemberApplication(Decimal uketukeNo) {
        Id jigyoId = jigyo().Id;
        Juji_Jigyo_Oubo__c app = new Juji_Jigyo_Oubo__c(
            Oubo_Juji_Jigyo__c = jigyoId,
            Oubo_Kaiin__c = member().Id,
            Oubo_Uketuke_No__c = uketukeNo
        );
        insert app;
        insert new List<Juji_Jigyo_Oubo_Meisai__c>{
            new Juji_Jigyo_Oubo_Meisai__c(
                Oubo_Meisa_Juji_Jigyo_Oubo__c = app.Id,
                Oubo_Meisa_Juji_Jigyo__c = jigyoId,
                Oubo_Meisa_Juji_Kano_Nengapi__c = Date.newInstance(2026, 11, 1),
                Oubo_Meisai_Kaisi_Jikoku__c = Time.newInstance(13, 0, 0, 0),
                Oubo_Meisai_Syuryo_Jikoku__c = Time.newInstance(15, 0, 0, 0)
            ),
            new Juji_Jigyo_Oubo_Meisai__c(
                Oubo_Meisa_Juji_Jigyo_Oubo__c = app.Id,
                Oubo_Meisa_Juji_Jigyo__c = jigyoId,
                Oubo_Meisa_Juji_Kano_Nengapi__c = Date.newInstance(2026, 11, 1),
                Oubo_Meisai_Kaisi_Jikoku__c = Time.newInstance(9, 0, 0, 0),
                Oubo_Meisai_Syuryo_Jikoku__c = Time.newInstance(12, 0, 0, 0)
            )
        };
        return [SELECT Id, SystemModstamp, Oubo_Uketuke_No__c FROM Juji_Jigyo_Oubo__c WHERE Id = :app.Id];
    }

    // ==================== toTime・toTimeText ====================
    // 時間の変換
    @IsTest
    static void toTime_conversion() {
        Assert.areEqual(Time.newInstance(9, 5, 0, 0), Juj_JigyoOboTourokuController.toTime('09:05'));
        Assert.isNull(Juj_JigyoOboTourokuController.toTime(null));
        Assert.areEqual('09:05', Juj_JigyoOboTourokuController.toTimeText(Time.newInstance(9, 5, 0, 0)));
        Assert.isNull(Juj_JigyoOboTourokuController.toTimeText(null));
    }

    // ==================== joinName ====================
    // 姓名の連結
    @IsTest
    static void joinName_joinsSeiMei() {
        Assert.areEqual('テスト タロウ', Juj_JigyoOboTourokuController.joinName('テスト', 'タロウ'));
        Assert.areEqual('テスト', Juj_JigyoOboTourokuController.joinName('テスト', null));
        Assert.areEqual('タロウ', Juj_JigyoOboTourokuController.joinName('', 'タロウ'));
        Assert.areEqual('', Juj_JigyoOboTourokuController.joinName(null, null));
    }

    // ==================== getJigyo ====================
    // 取得できる
    @IsTest
    static void getJigyo_found() {
        createMemberApplication(5);
        Map<String, Object> r = Juj_JigyoOboTourokuController.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual('テスト場所', get(r, 'basyoName'));
        Assert.areEqual('テスト事業', get(r, 'jigyo.jigyoName'));
        Assert.areEqual('001', get(r, 'jigyo.shibuCode'));
        Assert.areEqual('テスト支部', get(r, 'jigyo.shibuName'), '支部名は Jims_Sibu_Name__c（Name ではない）');
        Assert.areEqual(5, num(r, 'jigyo.lastUketukeNo'));
        // 入力フラグが未設定の場合は制限しない（必須なし・すべて入力可）
        Assert.areEqual(false, get(r, 'jigyo.inputControl.requiredWeekday'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.requiredKanoubi'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.requiredKibouNissu'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.requiredSkill'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.optionalSkill'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.optionalSkillNote'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.optionalChosho'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.optionalSodanKamoku'));
    }

    // 入力フラグによる入力制御
    @IsTest
    static void getJigyo_inputControlByFlags() {
        Juji_Jigyo__c j = jigyo();
        j.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Yobi__c = Juj_JigyoOboTourokuController.REQUIRED_ON;
        j.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Hi__c = '省略可';
        j.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kibo_Nisu__c = Juj_JigyoOboTourokuController.REQUIRED_ON;
        j.Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c = Juj_JigyoOboTourokuController.REQUIRED_ON;
        j.Juji_Ouboji_Nini_Nyuryoku_Flag_5Dankai__c = Juj_JigyoOboTourokuController.OPTIONAL_OFF;
        j.Juji_Ouboji_Nini_Nyuryoku_Flag_Skill_Tok__c = '許可';
        j.Juji_Ouboji_Nini_Nyuryoku_Flag_Tyosyo__c = Juj_JigyoOboTourokuController.OPTIONAL_OFF;
        j.Juji_Ouboji_Nini_Nyuryoku_Flag_Sodan__c = Juj_JigyoOboTourokuController.OPTIONAL_OFF;
        update j;

        Map<String, Object> r = Juj_JigyoOboTourokuController.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual(true, get(r, 'jigyo.inputControl.requiredWeekday'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.requiredKanoubi'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.requiredKibouNissu'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.requiredSkill'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.optionalSkill'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.optionalSkillNote'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.optionalChosho'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.optionalSodanKamoku'));
    }

    // 応募なしは最終受付番号が空白
    @IsTest
    static void getJigyo_noApplications_lastUketukeNoBlank() {
        Map<String, Object> r = Juj_JigyoOboTourokuController.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.isNull(get(r, 'jigyo.lastUketukeNo'));
    }

    // 従事場所Noのみ
    @IsTest
    static void getJigyo_basyoNoOnly() {
        Map<String, Object> r = Juj_JigyoOboTourokuController.getJigyo(null, BASYO_NO, null);
        Assert.areEqual('テスト場所', get(r, 'basyoName'));
        Assert.isNull(get(r, 'jigyo'));
    }

    // 事業なし
    @IsTest
    static void getJigyo_jigyoNotFound() {
        Map<String, Object> r = Juj_JigyoOboTourokuController.getJigyo(WRONG_JIGYO_NO, BASYO_NO, NENDO);
        Assert.isNull(get(r, 'jigyo'));
    }

    // ==================== getJujisha ====================
    // 会員
    @IsTest
    static void getJujisha_member() {
        Map<String, Object> j = Juj_JigyoOboTourokuController.getJujisha(MEMBER_NO);
        Assert.areEqual('MEMBER', get(j, 'jujishaType'));
        Assert.areEqual('テスト 太郎', get(j, 'name'));
        Assert.areEqual('テスト タロウ', get(j, 'furigana'), 'フリガナは姓・名を半角スペースで連結すること');
        Assert.areEqual('002', get(j, 'shibuCode'), '支部コードは会員が参照する事務所・法人から取得すること');
        Assert.areEqual('西支部', get(j, 'shibuName'), '支部名は Jims_Sibu_Name__c（Name ではない）');
        Assert.areEqual('東京都千代田区1-1-1', get(j, 'address'), '事務所住所は会員の項目から取得すること');
        Assert.areEqual('03-0000-0000', get(j, 'tel'));
        Assert.areEqual('03-0000-0001', get(j, 'fax'));
        Assert.isFalse(j.containsKey('recordId'), '内部用の ID は画面に返さないこと');
    }

    // 相談員
    @IsTest
    static void getJujisha_sodanin() {
        Map<String, Object> j = Juj_JigyoOboTourokuController.getJujisha(SODANIN_NO);
        Assert.areEqual('SODANIN', get(j, 'jujishaType'));
        Assert.areEqual('相談 花子', get(j, 'name'));
        Assert.areEqual('ソウダン ハナコ', get(j, 'furigana'));
        Assert.isNull(get(j, 'shibuName'));
    }

    // 取得できない
    @IsTest
    static void getJujisha_notFound() {
        Assert.isNull(Juj_JigyoOboTourokuController.getJujisha('0000000'));
        Assert.isNull(Juj_JigyoOboTourokuController.getJujisha(''));
    }

    // ==================== loadApplication：応募情報表示（従事事業キー＋番号） ====================
    // 番号・応募なし
    @IsTest
    static void loadApplication_byNo_noApplication() {
        Map<String, Object> r = Juj_JigyoOboTourokuController.loadApplication(null, JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual('テスト 太郎', get(r, 'jujisha.name'));
        Assert.isNull(get(r, 'application'));
    }

    // 番号・応募あり
    @IsTest
    static void loadApplication_byNo_withApplication() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Map<String, Object> r = Juj_JigyoOboTourokuController.loadApplication(null, JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual(String.valueOf(app.Id), get(r, 'application.applicationId'));
        List<Object> kanoubiDates = (List<Object>) get(r, 'application.kanoubiDates');
        Assert.areEqual(1, kanoubiDates.size());
        Map<String, Object> k = (Map<String, Object>) kanoubiDates[0];
        Assert.areEqual('2026-11-01', k.get('kanoubiDate'), '同じ日の明細は1日にまとめること');
        List<Object> slots = (List<Object>) k.get('timeSlots');
        Assert.areEqual(2, slots.size());
        Map<String, Object> slot = (Map<String, Object>) slots[0];
        Assert.areEqual('09:00', slot.get('startTime'), '開始時間の昇順');
        Assert.areEqual('12:00', slot.get('endTime'));
        Assert.areEqual('13:00', ((Map<String, Object>) slots[1]).get('startTime'));
    }

    // 番号・従事者なしはエラー
    @IsTest
    static void loadApplication_byNo_jujishaNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.loadApplication(null, JIGYO_NO, BASYO_NO, NENDO, '0000000');
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JUJISHA_NOT_FOUND[1], e.getMessage());
        }
    }

    // 番号・事業なしはエラー
    @IsTest
    static void loadApplication_byNo_jigyoNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.loadApplication(null, WRONG_JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== loadApplication：応募情報検索からの戻り（応募ID） ====================
    // 応募ID・取得できる
    @IsTest
    static void loadApplication_byId_found() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Map<String, Object> r = Juj_JigyoOboTourokuController.loadApplication(app.Id, null, null, null, null);
        Assert.areEqual(JIGYO_NO, get(r, 'jigyoKey.jujiJigyoNo'));
        Assert.areEqual(BASYO_NO, get(r, 'jigyoKey.jujiBasyoNo'));
        Assert.areEqual(NENDO, get(r, 'jigyoKey.jisiNendo'));
        Assert.areEqual(MEMBER_NO, get(r, 'jujishaNo'));
        Assert.areEqual(String.valueOf(app.Id), get(r, 'application.applicationId'));
        Assert.isNotNull(get(r, 'application.systemModstamp'));
    }

    // 応募ID・削除済みはエラー
    @IsTest
    static void loadApplication_byId_deleted_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        delete app;
        try {
            Juj_JigyoOboTourokuController.loadApplication(app.Id, null, null, null, null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_APPLICATION_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== checkJigyo ====================
    // 従事可能日入力・実施日なしはエラー
    @IsTest
    static void checkJigyo_kanoubi_noJisshibi_error() {
        try {
            Juj_JigyoOboTourokuController.checkJigyo(JIGYO_NO, BASYO_NO, NENDO, true);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_NO_JISSHIBI[1], e.getMessage());
        }
    }

    // 従事可能日入力・実施日あり
    @IsTest
    static void checkJigyo_kanoubi_withJisshibi_ok() {
        insert new Juji_Jigyo_Meisai__c(
            Juji_Meisai_Juji_Jigyo__c = jigyo().Id,
            Juji_Meisai_Jisi_Nengapi__c = Date.newInstance(2026, 11, 1)
        );
        Juj_JigyoOboTourokuController.checkJigyo(JIGYO_NO, BASYO_NO, NENDO, true);
        Assert.isTrue(true, '例外が発生しないこと');
    }

    // 従事可能日入力・事業なしはエラー
    @IsTest
    static void checkJigyo_kanoubi_jigyoNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.checkJigyo(WRONG_JIGYO_NO, BASYO_NO, NENDO, true);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== saveApplication ====================
    // 追加モード
    @IsTest
    static void saveApplication_addMode() {
        createMemberApplication(5);
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(SODANIN_NO);
        // 時間帯が1件も選択されていない日付は登録しない
        Juj_JigyoOboTourokuController.KanoubiDate noSlot = new Juj_JigyoOboTourokuController.KanoubiDate();
        noSlot.kanoubiDate = '2026-11-15';
        noSlot.timeSlots = new List<Juj_JigyoOboTourokuController.TimeSlot>();
        req.kanoubiDates.add(noSlot);
        Map<String, Object> r = save(req);
        Assert.areEqual(6, num(r, 'uketukeNo'), '最大値＋1 で採番されること');

        Juji_Jigyo_Oubo__c app = [
            SELECT Id, Oubo_Uketuke_No__c, Oubo_Soudanin_Master__c, Oubo_Kaiin__c, Oubo_Shimei__c, Oubo_Juji_Keiken__c,
                Oubo_Juji_Kano_Yobi_Flag_Mon__c, Oubo_Juji_Kano_Yobi_Flag_Tue__c,
                (SELECT Oubo_Meisa_Juji_Kano_Nengapi__c FROM Oubo_Meisa_Juji_Jigyo_Oubo__r)
            FROM Juji_Jigyo_Oubo__c
            WHERE Oubo_Soudanin_Master__c != null
        ];
        Assert.isNull(app.Oubo_Kaiin__c);
        Assert.areEqual('相談 花子', app.Oubo_Shimei__c, '氏名に従事者の氏名を設定すること');
        Assert.areEqual('有', app.Oubo_Juji_Keiken__c);
        Assert.areEqual(Juj_JigyoOboTourokuController.WEEKDAY_KA, app.Oubo_Juji_Kano_Yobi_Flag_Mon__c);
        Assert.areEqual(Juj_JigyoOboTourokuController.WEEKDAY_FUKA, app.Oubo_Juji_Kano_Yobi_Flag_Tue__c);
        Assert.areEqual(2, app.Oubo_Meisa_Juji_Jigyo_Oubo__r.size(), '時間帯のない日付は登録しないこと');
    }

    // 全日程従事可能は全曜日可
    @IsTest
    static void saveApplication_allDays_allWeekdaysKa() {
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(MEMBER_NO);
        req.form.allDays = true;
        req.form.weekdays = new List<String>();
        save(req);

        Map<String, Object> r = Juj_JigyoOboTourokuController.loadApplication(null, JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual(7, ((List<Object>) get(r, 'application.form.weekdays')).size());
        Assert.areEqual(1, ((List<Object>) get(r, 'application.form.skills')).size());
        Assert.areEqual('有', get(r, 'application.form.keiken'));
    }

    // 追加モードで登録済みはエラー
    @IsTest
    static void saveApplication_addMode_alreadyExists_error() {
        createMemberApplication(1);
        try {
            save(addRequest(MEMBER_NO));
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_ALREADY_EXISTS[1], e.getMessage());
        }
    }

    // 変更モードで受付番号0は採番
    @IsTest
    static void saveApplication_changeMode_uketukeNoZero_numbered() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(0);
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        req.kanoubiDates = new List<Juj_JigyoOboTourokuController.KanoubiDate>{ kanoubi('2026-11-15', '10:00', '11:00') };

        Map<String, Object> r = save(req);
        Assert.areEqual(1, num(r, 'uketukeNo'));
        Assert.areEqual('テスト 太郎', [SELECT Oubo_Shimei__c FROM Juji_Jigyo_Oubo__c WHERE Id = :app.Id].Oubo_Shimei__c);

        List<Juji_Jigyo_Oubo_Meisai__c> details = [
            SELECT Oubo_Meisa_Juji_Kano_Nengapi__c, Oubo_Meisai_Kaisi_Jikoku__c, Oubo_Meisai_Syuryo_Jikoku__c
            FROM Juji_Jigyo_Oubo_Meisai__c
            WHERE Oubo_Meisa_Juji_Jigyo_Oubo__c = :app.Id
        ];
        Assert.areEqual(1, details.size(), '外した時間帯は削除され、選択した時間帯のみになること');
        Assert.areEqual(Date.newInstance(2026, 11, 15), details[0].Oubo_Meisa_Juji_Kano_Nengapi__c);
        Assert.areEqual(Time.newInstance(10, 0, 0, 0), details[0].Oubo_Meisai_Kaisi_Jikoku__c);
        Assert.areEqual(Time.newInstance(11, 0, 0, 0), details[0].Oubo_Meisai_Syuryo_Jikoku__c);
    }

    // 1日に複数の時間帯は時間帯ごとに1件
    @IsTest
    static void saveApplication_multipleSlotsInDay_oneRecordPerSlot() {
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(MEMBER_NO);
        Juj_JigyoOboTourokuController.KanoubiDate k = kanoubi('2026-11-22', '09:00', '12:00');
        Juj_JigyoOboTourokuController.TimeSlot pm = new Juj_JigyoOboTourokuController.TimeSlot();
        pm.startTime = '13:00';
        pm.endTime = '15:00';
        k.timeSlots.add(pm);
        req.kanoubiDates = new List<Juj_JigyoOboTourokuController.KanoubiDate>{ k };
        save(req);
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Juji_Jigyo_Oubo_Meisai__c WHERE Oubo_Meisa_Juji_Kano_Nengapi__c = :Date.newInstance(2026, 11, 22)],
            '1日に2つの時間帯を選択した場合は2件登録されること'
        );
    }

    // 変更モードで採番済みは採番しない
    @IsTest
    static void saveApplication_changeMode_numbered_notRenumbered() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(5);
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);

        Map<String, Object> r = save(req);
        Assert.isNull(get(r, 'uketukeNo'));
        Assert.areEqual(5, [SELECT Oubo_Uketuke_No__c FROM Juji_Jigyo_Oubo__c WHERE Id = :app.Id].Oubo_Uketuke_No__c);
    }

    // 変更モードで削除済みはエラー
    @IsTest
    static void saveApplication_changeMode_deleted_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(MEMBER_NO);
        req.applicationId = app.Id;
        req.systemModstamp = app.SystemModstamp;
        delete app;
        try {
            save(req);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_UPDATE_NOT_FOUND[1], e.getMessage());
        }
    }

    // 変更モードで更新済みはエラー
    @IsTest
    static void saveApplication_changeMode_updatedByOther_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(MEMBER_NO);
        req.applicationId = app.Id;
        req.systemModstamp = app.SystemModstamp.addSeconds(-1);
        try {
            save(req);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            // 共通の排他チェックによるエラー（メッセージは共通側で定義）
            Assert.isNotNull(e);
        }
    }

    // 変更モード：変わらない時間帯はそのまま残し、外した時間帯は削除、新たに選択した時間帯は登録する
    @IsTest
    static void saveApplication_changeMode_detailsDiff() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Id keptId = details(app.Id)[1].Id; // 11/01 13:00-15:00
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        req.kanoubiDates = new List<Juj_JigyoOboTourokuController.KanoubiDate>{
            kanoubi('2026-11-01', '13:00', '15:00'),
            kanoubi('2026-11-15', '10:00', '11:00')
        };
        save(req);

        List<Juji_Jigyo_Oubo_Meisai__c> after = details(app.Id);
        Assert.areEqual(2, after.size());
        Assert.areEqual(keptId, after[0].Id, '変わらない時間帯は同じレコードのまま残ること');
        Assert.areEqual(Date.newInstance(2026, 11, 15), after[1].Oubo_Meisa_Juji_Kano_Nengapi__c, '新たに選択した時間帯が登録されること');
        Assert.areEqual(Time.newInstance(10, 0, 0, 0), after[1].Oubo_Meisai_Kaisi_Jikoku__c);
    }

    // 変更モード：従事可能日を変えない場合、明細は変更されない
    @IsTest
    static void saveApplication_changeMode_detailsUnchanged() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Set<Id> beforeIds = new Map<Id, Juji_Jigyo_Oubo_Meisai__c>(details(app.Id)).keySet();
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        req.kanoubiDates = new List<Juj_JigyoOboTourokuController.KanoubiDate>{
            kanoubi('2026-11-01', '09:00', '12:00'),
            kanoubi('2026-11-01', '13:00', '15:00')
        };
        save(req);
        Assert.areEqual(beforeIds, new Map<Id, Juji_Jigyo_Oubo_Meisai__c>(details(app.Id)).keySet());
    }

    // 変更モード：同じ時間帯が重複して登録されている場合は1件のみ残す。画面で重複している時間帯も1件のみ登録する
    @IsTest
    static void saveApplication_changeMode_duplicateDetails_keepOne() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        insert newDetail(app.Id, Date.newInstance(2026, 11, 1), 13, 15);
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        req.kanoubiDates = new List<Juj_JigyoOboTourokuController.KanoubiDate>{
            kanoubi('2026-11-01', '13:00', '15:00'),
            kanoubi('2026-11-01', '13:00', '15:00'),
            kanoubi('2026-11-20', '10:00', '11:00'),
            kanoubi('2026-11-20', '10:00', '11:00')
        };
        save(req);
        Assert.areEqual(2, details(app.Id).size(), '11/01 13:00-15:00 と 11/20 10:00-11:00 の1件ずつになること');
    }

    // 変更モード：読込後に他のユーザが明細を追加した場合はエラー
    @IsTest
    static void saveApplication_changeMode_detailAddedByOther_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        insert newDetail(app.Id, Date.newInstance(2026, 11, 29), 9, 12);
        assertDetailUpdatedError(req);
    }

    // 変更モード：読込後に他のユーザが明細を削除した場合はエラー
    @IsTest
    static void saveApplication_changeMode_detailDeletedByOther_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        delete details(app.Id)[0];
        assertDetailUpdatedError(req);
    }

    // 変更モード：読込後に他のユーザが明細を更新した場合（明細の最新のシステム更新日時が読込時より新しい）はエラー
    @IsTest
    static void saveApplication_changeMode_detailUpdatedByOther_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Juj_JigyoOboTourokuController.SaveRequest req = changeRequest(app);
        // 同一秒内の更新ではシステム更新日時が変わらない場合があるため、読込時の版を1秒前にして他ユーザの更新を再現する
        List<String> parts = req.meisaiVersion.split('_');
        req.meisaiVersion = parts[0] + '_' + (Long.valueOf(parts[1]) - 1000);
        assertDetailUpdatedError(req);
    }

    private static void assertDetailUpdatedError(Juj_JigyoOboTourokuController.SaveRequest req) {
        try {
            save(req);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_DETAIL_UPDATED[1], e.getMessage());
        }
    }

    // 明細の版：明細がない場合
    @IsTest
    static void meisaiVersion_noDetails() {
        Assert.areEqual('0_0', Juj_JigyoOboTourokuController.meisaiVersion(new List<Juji_Jigyo_Oubo_Meisai__c>()));
    }

    // 登録・正常
    @IsTest
    static void checkJigyo_save_ok() {
        Juj_JigyoOboTourokuController.checkJigyo(JIGYO_NO, BASYO_NO, NENDO, false);
        Assert.isTrue(true, '例外が発生しないこと');
    }

    // 登録・事業なしはエラー
    @IsTest
    static void checkJigyo_save_jigyoNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.checkJigyo(WRONG_JIGYO_NO, BASYO_NO, NENDO, false);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // 事業なしはエラー
    @IsTest
    static void saveApplication_jigyoNotFound_error() {
        Juj_JigyoOboTourokuController.SaveRequest req = addRequest(MEMBER_NO);
        req.jigyoKey.jujiJigyoNo = WRONG_JIGYO_NO;
        try {
            save(req);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // 従事者なしはエラー
    @IsTest
    static void saveApplication_jujishaNotFound_error() {
        try {
            save(addRequest('0000000'));
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JUJISHA_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== deleteApplication ====================
    // 削除できる
    @IsTest
    static void deleteApplication_deletes() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        Juj_JigyoOboTourokuController.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, app.SystemModstamp);
        Assert.areEqual(0, [SELECT COUNT() FROM Juji_Jigyo_Oubo__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM Juji_Jigyo_Oubo_Meisai__c], '明細も削除されること');
    }

    // 割当ありはエラー
    @IsTest
    static void deleteApplication_assigned_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        // 仮割当（割当フラグ＝1）
        insert new Juji_Jigyo_Wariate__c(
            Wari_Juji_Jigyo__c = jigyo().Id,
            Wari_Kaiin__c = member().Id,
            Wari_Juji_Nengapi__c = Date.newInstance(2026, 11, 1),
            Wari_Wriate_Flag__c = Juj_JigyoOboTourokuController.FLAG_ON
        );
        try {
            Juj_JigyoOboTourokuController.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, app.SystemModstamp);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_ASSIGNED[1], e.getMessage());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Juji_Jigyo_Oubo__c], '削除されないこと');
    }

    // 更新済みはエラー
    @IsTest
    static void deleteApplication_updatedByOther_error() {
        Juji_Jigyo_Oubo__c app = createMemberApplication(1);
        try {
            Juj_JigyoOboTourokuController.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, app.SystemModstamp.addSeconds(-1));
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            // 共通の排他チェックによるエラー（メッセージは共通側で定義）
            Assert.isNotNull(e);
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Juji_Jigyo_Oubo__c], '削除されないこと');
    }

    // 応募なしはエラー
    @IsTest
    static void deleteApplication_applicationNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_APPLICATION_NOT_FOUND[1], e.getMessage());
        }
    }

    // 事業なしはエラー
    @IsTest
    static void deleteApplication_jigyoNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.deleteApplication(WRONG_JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // 従事者なしはエラー
    @IsTest
    static void deleteApplication_jujishaNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, '0000000', null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JUJISHA_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== deleteAllApplications ====================
    // 全件削除できる
    @IsTest
    static void deleteAllApplications_deletesAll() {
        createMemberApplication(1);
        save(addRequest(SODANIN_NO));
        Juj_JigyoOboTourokuController.deleteAllApplications(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual(0, [SELECT COUNT() FROM Juji_Jigyo_Oubo__c]);
    }

    // 割当ありは1件も削除しない
    @IsTest
    static void deleteAllApplications_assigned_deletesNone() {
        createMemberApplication(1);
        save(addRequest(SODANIN_NO));
        // 相談員に確定した割当（確定フラグ＝1）
        insert new Juji_Jigyo_Wariate__c(
            Wari_Juji_Jigyo__c = jigyo().Id,
            Wari_Soudanin_Master__c = [SELECT Id FROM Soudanin_Master__c LIMIT 1].Id,
            Wari_Juji_Nengapi__c = Date.newInstance(2026, 11, 8),
            Wari_Kakutei_Flag__c = Juj_JigyoOboTourokuController.FLAG_ON
        );
        try {
            Juj_JigyoOboTourokuController.deleteAllApplications(JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_ASSIGNED[1], e.getMessage());
        }
        Assert.areEqual(2, [SELECT COUNT() FROM Juji_Jigyo_Oubo__c], '1件も削除されないこと');
    }

    // 応募なしはエラーとしない
    @IsTest
    static void deleteAllApplications_noApplications_noError() {
        Juj_JigyoOboTourokuController.deleteAllApplications(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual(0, [SELECT COUNT() FROM Juji_Jigyo_Oubo__c], '例外が発生しないこと（現行同様）');
    }

    // 事業なしはエラー
    @IsTest
    static void deleteAllApplications_jigyoNotFound_error() {
        try {
            Juj_JigyoOboTourokuController.deleteAllApplications(WRONG_JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(Juj_JigyoOboTourokuController.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }
}
