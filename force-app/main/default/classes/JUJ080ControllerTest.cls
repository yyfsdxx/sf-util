/**
 * JUJ080Controller のテストクラス
 * ※ オブジェクト名・項目名は論理名で記載している（API 名確定後に一括置換する）。
 * ※ テストデータの必須項目が不足する場合は setup に追加すること。
 * ※ コントローラの戻り値は Map<String, Object>（JSON 経由）のため、ヘルパーで値を取り出して検証する。
 */
@IsTest
private class JUJ080ControllerTest {

    private static final String JIGYO_NO = '0000001';
    private static final String BASYO_NO = '0000000001';
    private static final String NENDO = '2026';
    private static final String WRONG_JIGYO_NO = '9999999';
    private static final String MEMBER_NO = '1234567';
    private static final String SODANIN_NO = '7654321';

    @TestSetup
    static void setup() {
        Account shibu = new Account(Name = 'テスト支部', 支部コード__c = '001');
        insert shibu;
        従事場所マスタ__c basyo = new 従事場所マスタ__c(従事場所No__c = BASYO_NO, 従事場所名__c = 'テスト場所');
        insert basyo;
        insert new 従事事業__c(
            従事事業No__c = JIGYO_NO,
            従事場所__c = basyo.Id,
            実施年度__c = NENDO,
            従事事業名__c = 'テスト事業',
            支部__c = shibu.Id
        );
        // 会員の支部・事務所情報は参照先の事務所・法人（Account）から取得する
        // ※ 支部名は事務所・法人の名称（Name）
        Account office = new Account(
            Name = 'テスト支部',
            支部コード__c = '001',
            事務所住所__c = '東京都千代田区1-1-1',
            事務所電話番号__c = '03-0000-0000',
            事務所FAX番号__c = '03-0000-0001'
        );
        insert office;
        // 会員は取引先責任者（Contact）。Name はロケールにより姓名の順序が変わるため、姓のみに氏名全体を設定する
        insert new Contact(
            登録番号__c = MEMBER_NO,
            LastName = 'テスト 太郎',
            フリガナ_姓__c = 'テスト',
            フリガナ_名__c = 'タロウ',
            事務所__c = office.Id
        );
        insert new 相談員__c(相談員番号__c = SODANIN_NO, 氏名__c = '相談 花子', フリガナ__c = 'ソウダン ハナコ');
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

    private static JUJ080Controller.JigyoKey key() {
        JUJ080Controller.JigyoKey k = new JUJ080Controller.JigyoKey();
        k.jujiJigyoNo = JIGYO_NO;
        k.jujiBasyoNo = BASYO_NO;
        k.jisiNendo = NENDO;
        return k;
    }

    private static JUJ080Controller.ApplicationForm form() {
        JUJ080Controller.ApplicationForm f = new JUJ080Controller.ApplicationForm();
        f.telFixed = '03-1111-1111';
        f.mail = 'test@example.com';
        f.allDays = false;
        f.weekdays = new List<String>{ '月', '水' };
        f.kibouNissu = '3';
        f.keiken = '1';
        JUJ080Controller.SkillValue skill = new JUJ080Controller.SkillValue();
        skill.field = JUJ080Controller.SKILL_FIELDS[0];
        skill.value = '5';
        f.skills = new List<JUJ080Controller.SkillValue>{ skill };
        f.sodanKamoku = '所得税';
        return f;
    }

    private static JUJ080Controller.SaveRequest addRequest(String jujishaNo) {
        JUJ080Controller.SaveRequest req = new JUJ080Controller.SaveRequest();
        req.jigyoKey = key();
        req.jujishaNo = jujishaNo;
        req.form = form();
        req.kanoubiDates = new List<JUJ080Controller.KanoubiDate>{
            kanoubi('2026-11-01', '13:00', '15:00'),
            kanoubi('2026-11-08', '09:00', '12:00')
        };
        return req;
    }

    // 従事可能日（時間帯1件）
    private static JUJ080Controller.KanoubiDate kanoubi(String kanoubiDate, String startTime, String endTime) {
        JUJ080Controller.TimeSlot slot = new JUJ080Controller.TimeSlot();
        slot.startTime = startTime;
        slot.endTime = endTime;
        JUJ080Controller.KanoubiDate k = new JUJ080Controller.KanoubiDate();
        k.kanoubiDate = kanoubiDate;
        k.timeSlots = new List<JUJ080Controller.TimeSlot>{ slot };
        return k;
    }

    // 画面と同じく JSON 文字列で登録処理を呼び出す
    private static Map<String, Object> save(JUJ080Controller.SaveRequest req) {
        return JUJ080Controller.saveApplication(JSON.serialize(req));
    }

    private static 従事事業__c jigyo() {
        return [SELECT Id FROM 従事事業__c WHERE 従事事業No__c = :JIGYO_NO LIMIT 1];
    }

    private static Contact member() {
        return [SELECT Id FROM Contact WHERE 登録番号__c = :MEMBER_NO LIMIT 1];
    }

    // 会員の応募を作成する（明細1件付き）
    private static 従事事業応募__c createMemberApplication(Decimal uketukeNo) {
        Id jigyoId = jigyo().Id;
        従事事業応募__c app = new 従事事業応募__c(従事事業__c = jigyoId, 会員__c = member().Id, 受付番号__c = uketukeNo);
        insert app;
        insert new 従事事業応募明細__c(
            従事事業応募__c = app.Id,
            従事事業__c = jigyoId,
            従事可能日__c = Date.newInstance(2026, 11, 1),
            時間帯__c = '[{"startTime":"13:00","endTime":"15:00","unused":"x"}]' // 使用しない項目は無視される
        );
        return [SELECT Id, SystemModstamp, 受付番号__c FROM 従事事業応募__c WHERE Id = :app.Id];
    }

    // ==================== parseTimeSlots ====================
    @IsTest
    static void parseTimeSlots_未設定・形式不正は空() {
        Assert.areEqual(0, JUJ080Controller.parseTimeSlots(null).size());
        Assert.areEqual(0, JUJ080Controller.parseTimeSlots('not json').size());
        Assert.areEqual(1, JUJ080Controller.parseTimeSlots('[{"startTime":"13:00","endTime":"15:00"}]').size());
    }

    // ==================== joinName ====================
    @IsTest
    static void joinName_姓名の連結() {
        Assert.areEqual('テスト タロウ', JUJ080Controller.joinName('テスト', 'タロウ'));
        Assert.areEqual('テスト', JUJ080Controller.joinName('テスト', null));
        Assert.areEqual('タロウ', JUJ080Controller.joinName('', 'タロウ'));
        Assert.areEqual('', JUJ080Controller.joinName(null, null));
    }

    // ==================== getJigyo ====================
    @IsTest
    static void getJigyo_取得できる() {
        createMemberApplication(5);
        Map<String, Object> r = JUJ080Controller.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual('テスト場所', get(r, 'basyoName'));
        Assert.areEqual('テスト事業', get(r, 'jigyo.jigyoName'));
        Assert.areEqual('001', get(r, 'jigyo.shibuCode'));
        Assert.areEqual('テスト支部', get(r, 'jigyo.shibuName'));
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

    @IsTest
    static void getJigyo_入力フラグによる入力制御() {
        従事事業__c j = jigyo();
        j.必須入力フラグ_従事可能曜日__c = JUJ080Controller.REQUIRED_ON;
        j.必須入力フラグ_従事可能日__c = '省略可';
        j.必須入力フラグ_希望従事日数__c = JUJ080Controller.REQUIRED_ON;
        j.必須入力フラグ_スキル__c = JUJ080Controller.REQUIRED_ON;
        j.任意入力フラグ_スキル__c = JUJ080Controller.OPTIONAL_OFF;
        j.任意入力フラグ_スキル特記事項__c = '許可';
        j.任意入力フラグ_主な著書論文__c = JUJ080Controller.OPTIONAL_OFF;
        j.任意入力フラグ_相談科目__c = JUJ080Controller.OPTIONAL_OFF;
        update j;

        Map<String, Object> r = JUJ080Controller.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual(true, get(r, 'jigyo.inputControl.requiredWeekday'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.requiredKanoubi'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.requiredKibouNissu'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.requiredSkill'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.optionalSkill'));
        Assert.areEqual(true, get(r, 'jigyo.inputControl.optionalSkillNote'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.optionalChosho'));
        Assert.areEqual(false, get(r, 'jigyo.inputControl.optionalSodanKamoku'));
    }

    @IsTest
    static void getJigyo_応募なしは最終受付番号が空白() {
        Map<String, Object> r = JUJ080Controller.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.isNull(get(r, 'jigyo.lastUketukeNo'));
    }

    @IsTest
    static void getJigyo_従事場所Noのみ() {
        Map<String, Object> r = JUJ080Controller.getJigyo(null, BASYO_NO, null);
        Assert.areEqual('テスト場所', get(r, 'basyoName'));
        Assert.isNull(get(r, 'jigyo'));
    }

    @IsTest
    static void getJigyo_事業なし() {
        Map<String, Object> r = JUJ080Controller.getJigyo(WRONG_JIGYO_NO, BASYO_NO, NENDO);
        Assert.isNull(get(r, 'jigyo'));
    }

    // ==================== getJujisha ====================
    @IsTest
    static void getJujisha_会員() {
        Map<String, Object> j = JUJ080Controller.getJujisha(MEMBER_NO);
        Assert.areEqual('MEMBER', get(j, 'jujishaType'));
        Assert.areEqual('テスト 太郎', get(j, 'name'));
        Assert.areEqual('テスト タロウ', get(j, 'furigana'), 'フリガナは姓・名を半角スペースで連結すること');
        Assert.areEqual('テスト支部', get(j, 'shibuName'));
        Assert.areEqual('東京都千代田区1-1-1', get(j, 'address'));
        Assert.areEqual('03-0000-0000', get(j, 'tel'));
        Assert.isFalse(j.containsKey('recordId'), '内部用の ID は画面に返さないこと');
    }

    @IsTest
    static void getJujisha_相談員() {
        Map<String, Object> j = JUJ080Controller.getJujisha(SODANIN_NO);
        Assert.areEqual('SODANIN', get(j, 'jujishaType'));
        Assert.isNull(get(j, 'shibuName'));
    }

    @IsTest
    static void getJujisha_取得できない() {
        Assert.isNull(JUJ080Controller.getJujisha('0000000'));
        Assert.isNull(JUJ080Controller.getJujisha(''));
    }

    // ==================== showApplication ====================
    @IsTest
    static void showApplication_応募なし() {
        Map<String, Object> r = JUJ080Controller.showApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual('テスト 太郎', get(r, 'jujisha.name'));
        Assert.isNull(get(r, 'application'));
    }

    @IsTest
    static void showApplication_応募あり() {
        従事事業応募__c app = createMemberApplication(1);
        Map<String, Object> r = JUJ080Controller.showApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual(String.valueOf(app.Id), get(r, 'application.applicationId'));
        List<Object> kanoubiDates = (List<Object>) get(r, 'application.kanoubiDates');
        Assert.areEqual(1, kanoubiDates.size());
        Map<String, Object> k = (Map<String, Object>) kanoubiDates[0];
        Assert.areEqual('2026-11-01', k.get('kanoubiDate'));
        Map<String, Object> slot = (Map<String, Object>) ((List<Object>) k.get('timeSlots'))[0];
        Assert.areEqual('13:00', slot.get('startTime'));
        Assert.areEqual('15:00', slot.get('endTime'));
    }

    @IsTest
    static void showApplication_従事者なしはエラー() {
        try {
            JUJ080Controller.showApplication(JIGYO_NO, BASYO_NO, NENDO, '0000000');
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JUJISHA_NOT_FOUND[1], e.getMessage());
        }
    }

    @IsTest
    static void showApplication_事業なしはエラー() {
        try {
            JUJ080Controller.showApplication(WRONG_JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== getApplication ====================
    @IsTest
    static void getApplication_取得できる() {
        従事事業応募__c app = createMemberApplication(1);
        Map<String, Object> r = JUJ080Controller.getApplication(app.Id);
        Assert.areEqual(JIGYO_NO, get(r, 'jigyoKey.jujiJigyoNo'));
        Assert.areEqual(BASYO_NO, get(r, 'jigyoKey.jujiBasyoNo'));
        Assert.areEqual(NENDO, get(r, 'jigyoKey.jisiNendo'));
        Assert.areEqual(MEMBER_NO, get(r, 'jujishaNo'));
        Assert.areEqual(String.valueOf(app.Id), get(r, 'application.applicationId'));
        Assert.isNotNull(get(r, 'application.systemModstamp'));
    }

    @IsTest
    static void getApplication_削除済みはエラー() {
        従事事業応募__c app = createMemberApplication(1);
        delete app;
        try {
            JUJ080Controller.getApplication(app.Id);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_APPLICATION_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== checkKanoubiInput ====================
    @IsTest
    static void checkKanoubiInput_実施日なしはエラー() {
        try {
            JUJ080Controller.checkKanoubiInput(JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_NO_JISSHIBI[1], e.getMessage());
        }
    }

    @IsTest
    static void checkKanoubiInput_実施日あり() {
        insert new 従事事業明細__c(従事事業__c = jigyo().Id, 実施日__c = Date.newInstance(2026, 11, 1));
        JUJ080Controller.checkKanoubiInput(JIGYO_NO, BASYO_NO, NENDO);
        Assert.isTrue(true, '例外が発生しないこと');
    }

    @IsTest
    static void checkKanoubiInput_事業なしはエラー() {
        try {
            JUJ080Controller.checkKanoubiInput(WRONG_JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== saveApplication ====================
    @IsTest
    static void saveApplication_追加モード() {
        createMemberApplication(5);
        Map<String, Object> r = save(addRequest(SODANIN_NO));
        Assert.areEqual(6, num(r, 'uketukeNo'), '最大値＋1 で採番されること');

        従事事業応募__c app = [
            SELECT Id, 受付番号__c, 相談員__c, 会員__c, 従事可能曜日フラグ_月__c, 従事可能曜日フラグ_火__c,
                (SELECT 従事可能日__c FROM 従事事業応募明細__r)
            FROM 従事事業応募__c
            WHERE 相談員__c != null
        ];
        Assert.isNull(app.会員__c);
        Assert.areEqual(JUJ080Controller.WEEKDAY_KA, app.従事可能曜日フラグ_月__c);
        Assert.areEqual(JUJ080Controller.WEEKDAY_FUKA, app.従事可能曜日フラグ_火__c);
        Assert.areEqual(2, app.従事事業応募明細__r.size());
    }

    @IsTest
    static void saveApplication_全日程従事可能は全曜日可() {
        JUJ080Controller.SaveRequest req = addRequest(MEMBER_NO);
        req.form.allDays = true;
        req.form.weekdays = new List<String>();
        save(req);

        Map<String, Object> r = JUJ080Controller.showApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual(7, ((List<Object>) get(r, 'application.form.weekdays')).size());
        Assert.areEqual(1, ((List<Object>) get(r, 'application.form.skills')).size());
    }

    @IsTest
    static void saveApplication_追加モードで登録済みはエラー() {
        createMemberApplication(1);
        try {
            save(addRequest(MEMBER_NO));
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_ALREADY_EXISTS[1], e.getMessage());
        }
    }

    @IsTest
    static void saveApplication_変更モードで受付番号0は採番() {
        従事事業応募__c app = createMemberApplication(0);
        JUJ080Controller.SaveRequest req = addRequest(MEMBER_NO);
        req.applicationId = app.Id;
        req.systemModstamp = app.SystemModstamp;
        req.kanoubiDates = new List<JUJ080Controller.KanoubiDate>{ kanoubi('2026-11-15', '10:00', '11:00') };

        Map<String, Object> r = save(req);
        Assert.areEqual(1, num(r, 'uketukeNo'));

        List<従事事業応募明細__c> details = [SELECT 従事可能日__c, 時間帯__c FROM 従事事業応募明細__c WHERE 従事事業応募__c = :app.Id];
        Assert.areEqual(1, details.size(), '明細が置き換えられること');
        Assert.areEqual(Date.newInstance(2026, 11, 15), details[0].従事可能日__c);
        Assert.areEqual('[{"startTime":"10:00","endTime":"11:00"}]', details[0].時間帯__c);
    }

    @IsTest
    static void saveApplication_変更モードで採番済みは採番しない() {
        従事事業応募__c app = createMemberApplication(5);
        JUJ080Controller.SaveRequest req = addRequest(MEMBER_NO);
        req.applicationId = app.Id;
        req.systemModstamp = app.SystemModstamp;

        Map<String, Object> r = save(req);
        Assert.isNull(get(r, 'uketukeNo'));
        Assert.areEqual(5, [SELECT 受付番号__c FROM 従事事業応募__c WHERE Id = :app.Id].受付番号__c);
    }

    @IsTest
    static void saveApplication_変更モードで削除済みはエラー() {
        従事事業応募__c app = createMemberApplication(1);
        JUJ080Controller.SaveRequest req = addRequest(MEMBER_NO);
        req.applicationId = app.Id;
        req.systemModstamp = app.SystemModstamp;
        delete app;
        try {
            save(req);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_DELETED[1], e.getMessage());
        }
    }

    @IsTest
    static void saveApplication_変更モードで更新済みはエラー() {
        従事事業応募__c app = createMemberApplication(1);
        JUJ080Controller.SaveRequest req = addRequest(MEMBER_NO);
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

    @IsTest
    static void checkSave_正常() {
        JUJ080Controller.checkSave(JIGYO_NO, BASYO_NO, NENDO);
        Assert.isTrue(true, '例外が発生しないこと');
    }

    @IsTest
    static void checkSave_事業なしはエラー() {
        try {
            JUJ080Controller.checkSave(WRONG_JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    @IsTest
    static void saveApplication_事業なしはエラー() {
        JUJ080Controller.SaveRequest req = addRequest(MEMBER_NO);
        req.jigyoKey.jujiJigyoNo = WRONG_JIGYO_NO;
        try {
            save(req);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    @IsTest
    static void saveApplication_従事者なしはエラー() {
        try {
            save(addRequest('0000000'));
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JUJISHA_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== deleteApplication ====================
    @IsTest
    static void deleteApplication_削除できる() {
        従事事業応募__c app = createMemberApplication(1);
        JUJ080Controller.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, app.SystemModstamp);
        Assert.areEqual(0, [SELECT COUNT() FROM 従事事業応募__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM 従事事業応募明細__c], '明細も削除されること');
    }

    @IsTest
    static void deleteApplication_割当ありはエラー() {
        従事事業応募__c app = createMemberApplication(1);
        // 仮割当（割当フラグ＝1）
        insert new 従事事業割当__c(
            従事事業__c = jigyo().Id,
            会員__c = member().Id,
            従事日__c = Date.newInstance(2026, 11, 1),
            割当フラグ__c = JUJ080Controller.FLAG_ON
        );
        try {
            JUJ080Controller.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, app.SystemModstamp);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_ASSIGNED[1], e.getMessage());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM 従事事業応募__c], '削除されないこと');
    }

    @IsTest
    static void deleteApplication_更新済みはエラー() {
        従事事業応募__c app = createMemberApplication(1);
        try {
            JUJ080Controller.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, app.SystemModstamp.addSeconds(-1));
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            // 共通の排他チェックによるエラー（メッセージは共通側で定義）
            Assert.isNotNull(e);
        }
        Assert.areEqual(1, [SELECT COUNT() FROM 従事事業応募__c], '削除されないこと');
    }

    @IsTest
    static void deleteApplication_応募なしはエラー() {
        try {
            JUJ080Controller.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_APPLICATION_NOT_FOUND[1], e.getMessage());
        }
    }

    @IsTest
    static void deleteApplication_事業なしはエラー() {
        try {
            JUJ080Controller.deleteApplication(WRONG_JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO, null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }

    @IsTest
    static void deleteApplication_従事者なしはエラー() {
        try {
            JUJ080Controller.deleteApplication(JIGYO_NO, BASYO_NO, NENDO, '0000000', null);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JUJISHA_NOT_FOUND[1], e.getMessage());
        }
    }

    // ==================== deleteAllApplications ====================
    @IsTest
    static void deleteAllApplications_全件削除できる() {
        createMemberApplication(1);
        save(addRequest(SODANIN_NO));
        JUJ080Controller.deleteAllApplications(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual(0, [SELECT COUNT() FROM 従事事業応募__c]);
    }

    @IsTest
    static void deleteAllApplications_割当ありは1件も削除しない() {
        createMemberApplication(1);
        save(addRequest(SODANIN_NO));
        // 相談員に確定した割当（確定フラグ＝1）
        insert new 従事事業割当__c(
            従事事業__c = jigyo().Id,
            相談員__c = [SELECT Id FROM 相談員__c LIMIT 1].Id,
            従事日__c = Date.newInstance(2026, 11, 8),
            確定フラグ__c = JUJ080Controller.FLAG_ON
        );
        try {
            JUJ080Controller.deleteAllApplications(JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_ASSIGNED[1], e.getMessage());
        }
        Assert.areEqual(2, [SELECT COUNT() FROM 従事事業応募__c], '1件も削除されないこと');
    }

    @IsTest
    static void deleteAllApplications_応募なしはエラー() {
        try {
            JUJ080Controller.deleteAllApplications(JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_NO_APPLICATIONS[1], e.getMessage());
        }
    }

    @IsTest
    static void deleteAllApplications_事業なしはエラー() {
        try {
            JUJ080Controller.deleteAllApplications(WRONG_JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ080Controller.E_JIGYO_NOT_FOUND[1], e.getMessage());
        }
    }
}
