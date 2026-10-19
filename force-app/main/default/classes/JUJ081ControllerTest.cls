/**
 * JUJ081Controller のテストクラス
 * ※ オブジェクト名・項目名は論理名で記載している（API 名確定後に一括置換する）。
 * ※ テストデータの必須項目が不足する場合は setup に追加すること。
 * ※ 開始時間・終了時間は型が未確定のため、テストデータには設定しない（toTimeText で個別に確認する）。
 */
@IsTest
private class JUJ081ControllerTest {

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
        従事事業__c jigyo = new 従事事業__c(
            従事事業No__c = JIGYO_NO,
            従事場所__c = basyo.Id,
            実施年度__c = NENDO,
            従事事業名__c = 'テスト事業',
            支部__c = shibu.Id
        );
        insert jigyo;
        // 実施日：11/3（時間帯2件。順序は逆に登録し、使用しない項目も含める）、11/10（時間帯1件）、12/1
        insert new List<従事事業明細__c>{
            new 従事事業明細__c(
                従事事業__c = jigyo.Id,
                実施日__c = Date.newInstance(2026, 11, 3),
                募集人数__c = 5,
                備考__c = '午前・午後',
                時間帯__c = '[{"startTime":"13:00","endTime":"15:00","count":2,"shiharaiKingaku":"1000"},'
                    + '{"startTime":"09:00","endTime":"12:00","count":3}]'
            ),
            new 従事事業明細__c(
                従事事業__c = jigyo.Id,
                実施日__c = Date.newInstance(2026, 11, 10),
                募集人数__c = 1,
                時間帯__c = '[{"startTime":"10:00","endTime":"11:00","count":1}]'
            ),
            new 従事事業明細__c(
                従事事業__c = jigyo.Id,
                実施日__c = Date.newInstance(2026, 12, 1),
                募集人数__c = 2,
                時間帯__c = '[{"startTime":"10:00","endTime":"11:00","count":2}]'
            )
        };
        Contact member = new Contact(登録番号__c = MEMBER_NO, LastName = 'テスト 太郎');
        insert member;
        相談員__c sodanin = new 相談員__c(相談員番号__c = SODANIN_NO, 氏名__c = '相談 花子');
        insert sodanin;

        // 割当：会員は 11/10 に仮割当（本人割当済）、相談員は 11/3 の 09:00-12:00 に確定
        insert new List<従事事業割当__c>{
            new 従事事業割当__c(
                従事事業__c = jigyo.Id,
                会員__c = member.Id,
                従事日__c = Date.newInstance(2026, 11, 10),
                割当フラグ__c = JUJ081Controller.FLAG_ON,
                時間帯__c = '[{"startTime":"10:00","endTime":"11:00"}]'
            ),
            new 従事事業割当__c(
                従事事業__c = jigyo.Id,
                相談員__c = sodanin.Id,
                従事日__c = Date.newInstance(2026, 11, 3),
                確定フラグ__c = JUJ081Controller.FLAG_ON,
                時間帯__c = '[{"startTime":"09:00","endTime":"12:00","unused":"x"}]'
            )
        };
    }

    // ==================== ヘルパー ====================
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

    private static void assertAuraError(List<String> expected, Exception e) {
        Assert.isInstanceOfType(e, AuraHandledException.class);
        Assert.areEqual(expected[1], e.getMessage());
    }

    // ==================== init ====================
    @IsTest
    static void init_会員() {
        Map<String, Object> r = JUJ081Controller.init(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.areEqual('テスト事業', get(r, 'jigyo.jigyoName'));
        Assert.areEqual('001', get(r, 'jigyo.shibuCode'));
        Assert.areEqual('テスト支部', get(r, 'jigyo.shibuName'));
        Assert.areEqual('テスト場所', get(r, 'jigyo.basyoName'));
        Assert.areEqual('テスト 太郎', get(r, 'jujishaName'));
        Assert.areEqual('2026-11-03', get(r, 'minJisshibi'));
        Assert.areEqual('2026-12-01', get(r, 'maxJisshibi'));
        // 本人割当済（仮割当を含む）
        List<Object> own = (List<Object>) get(r, 'ownAssigned');
        Assert.areEqual(1, own.size());
        Map<String, Object> k = (Map<String, Object>) own[0];
        Assert.areEqual('2026-11-10', k.get('kanoubiDate'));
        Map<String, Object> slot = (Map<String, Object>) ((List<Object>) k.get('timeSlots'))[0];
        Assert.areEqual('10:00', slot.get('startTime'));
        Assert.areEqual('11:00', slot.get('endTime'));
    }

    @IsTest
    static void init_相談員() {
        Map<String, Object> r = JUJ081Controller.init(JIGYO_NO, BASYO_NO, NENDO, SODANIN_NO);
        Assert.areEqual('相談 花子', get(r, 'jujishaName'));
        Assert.areEqual('2026-11-03', get((Map<String, Object>) ((List<Object>) get(r, 'ownAssigned'))[0], 'kanoubiDate'));
    }

    @IsTest
    static void init_実施日なしは範囲null() {
        delete [SELECT Id FROM 従事事業明細__c];
        Map<String, Object> r = JUJ081Controller.init(JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
        Assert.isNull(get(r, 'minJisshibi'));
        Assert.isNull(get(r, 'maxJisshibi'));
    }

    @IsTest
    static void init_事業なしはエラー() {
        try {
            JUJ081Controller.init(WRONG_JIGYO_NO, BASYO_NO, NENDO, MEMBER_NO);
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(JUJ081Controller.E_JIGYO_NOT_FOUND, e);
        }
    }

    @IsTest
    static void init_従事者なしはエラー() {
        try {
            JUJ081Controller.init(JIGYO_NO, BASYO_NO, NENDO, '9999999');
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(JUJ081Controller.E_JUJISHA_NOT_FOUND, e);
        }
    }

    @IsTest
    static void init_番号未入力はエラー() {
        try {
            JUJ081Controller.init(JIGYO_NO, BASYO_NO, NENDO, '');
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(JUJ081Controller.E_JUJISHA_NOT_FOUND, e);
        }
    }

    // ==================== getDays ====================
    @IsTest
    static void getDays_表示期間内の実施日と時間帯() {
        List<Map<String, Object>> days = JUJ081Controller.getDays(JIGYO_NO, BASYO_NO, NENDO, '2026-11-01', '2026-11-30');
        Assert.areEqual(2, days.size(), '12/1 は表示期間外');

        Map<String, Object> day = days[0];
        Assert.areEqual('2026-11-03', day.get('jisshibi'));
        Assert.areEqual(5, day.get('boshuNinzu'));
        Assert.areEqual('午前・午後', day.get('biko'));
        Assert.areEqual(1, day.get('wariateNinzu'), '確定した割当の件数');

        List<Object> slots = (List<Object>) day.get('timeSlots');
        Assert.areEqual(2, slots.size());
        Map<String, Object> first = (Map<String, Object>) slots[0];
        Assert.areEqual('09:00', first.get('startTime'), '開始時間の昇順');
        Assert.areEqual('12:00', first.get('endTime'));
        Assert.areEqual(3, first.get('count'));
        Assert.areEqual(1, first.get('wariateNinzu'), 'その時間帯を含む確定割当の件数');
        Map<String, Object> second = (Map<String, Object>) slots[1];
        Assert.areEqual('13:00', second.get('startTime'));
        Assert.areEqual(0, second.get('wariateNinzu'));
        Assert.areEqual(0, days[1].get('wariateNinzu'), '仮割当は割当人数に含めない');
    }

    @IsTest
    static void getDays_事業なしはエラー() {
        try {
            JUJ081Controller.getDays(WRONG_JIGYO_NO, BASYO_NO, NENDO, '2026-11-01', '2026-11-30');
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(JUJ081Controller.E_JIGYO_NOT_FOUND, e);
        }
    }

    // ==================== checkSave ====================
    @IsTest
    static void checkSave_正常() {
        JUJ081Controller.checkSave(JIGYO_NO, BASYO_NO, NENDO);
        Assert.isTrue(true, '例外が発生しないこと');
    }

    @IsTest
    static void checkSave_事業なしはエラー() {
        try {
            JUJ081Controller.checkSave(WRONG_JIGYO_NO, BASYO_NO, NENDO);
            Assert.fail('例外が発生すること');
        } catch (Exception e) {
            assertAuraError(JUJ081Controller.E_JIGYO_NOT_FOUND, e);
        }
    }

    // ==================== 変換 ====================
    @IsTest
    static void parseSlots_未設定・形式不正は空() {
        Assert.areEqual(0, JUJ081Controller.parseSlots(null).size());
        Assert.areEqual(0, JUJ081Controller.parseSlots('not json').size());
    }

    @IsTest
    static void toTimeText_時間型とテキスト() {
        Assert.isNull(JUJ081Controller.toTimeText(null));
        Assert.areEqual('09:30', JUJ081Controller.toTimeText(Time.newInstance(9, 30, 0, 0)));
        Assert.areEqual('13:00', JUJ081Controller.toTimeText('13:00'));
    }

    @IsTest
    static void slotKey_開始と終了() {
        Assert.areEqual('09:00-12:00', JUJ081Controller.slotKey('09:00', '12:00'));
    }
}
