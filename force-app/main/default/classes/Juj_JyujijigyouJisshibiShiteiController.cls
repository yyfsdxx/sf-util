/**
 * JUJ081 従事可能日指定 コントローラ
 * 設計書：機能設計書 処理詳細（JUJ080／081／082 共通シート）
 *   コメント中の番号は「1.画面アクション No.」「4.入力チェック No.」「5.データ更新 (n)」に対応する。
 *
 * ※ 本画面は DB を更新しない（参照のみ）。選択結果は JUJ080 へ返却し、JUJ080 の登録時に登録する。
 * ※ SOQL はすべてユーザモードで実行し、支部の条件は付けない。
 * ※ 画面から受け取った Id は使用せず、従事事業キー・番号から都度取得する。
 * ※ 一括割当実行中チェックは共通（Juj_CommonController）を呼び出す（エラー時は共通側で AuraHandledException を発生させる）。
 * ※ LWC から呼び出すメソッドは内部クラスを引数・戻り値に使用できないため、
 *   引数は基本型、戻り値は Map／List<Map> とする。
 */
public with sharing class Juj_JyujijigyouJisshibiShiteiController {

    // ==================== 定数 ====================
    // メッセージ（{メッセージID, 文言}）【要確認 QA-20】ID は暫定
    // ※ 正常な操作では発生しない防御的なチェック（JUJ080 で事業・従事者を確認してから開く）のため、4.入力チェックには記載しない
    @TestVisible
    private static final List<String> E_JIGYO_NOT_FOUND = new List<String>{ 'JUJ081-E001', '従事事業が存在しません。' };
    @TestVisible
    private static final List<String> E_JUJISHA_NOT_FOUND = new List<String>{ 'WLP007-0009', '従事者が存在しません。' };

    private static final String TIME_FORMAT = 'HH:mm';

    // 一括割当チェック（共通）の checkKeys（現在は未使用のため空）
    private static final Set<String> NO_CHECK_KEYS = new Set<String>();

    // 割当のフラグ項目（割当フラグ・確定フラグ）は選択リスト。値 '1' で ON（仮割当・確定）
    @TestVisible
    private static final String FLAG_ON = '1';

    // ==================== 画面アクション No.21 画面初期化 ====================
    // 戻り値：{ jigyo: { jigyoName, shibuCode, shibuName, basyoName }, jujishaName,
    //          ownAssigned: [{ kanoubiDate, timeSlots: [{ startTime, endTime }] }],
    //          minJisshibi: 'yyyy-MM-dd' | null, maxJisshibi: 'yyyy-MM-dd' | null }
    @AuraEnabled
    public static Map<String, Object> init(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, String jujishaNo) {
        try {
            // 従事事業キーが一致する従事事業を取得する。取得できない場合はエラー（画面を閉じ、JUJ080 に表示する）
            Juji_Jigyo__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // 登録番号/相談員番号が一致する会員または相談員を取得する。取得できない場合はエラー（同上）
            Jujisha jujisha = findJujisha(jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }

            InitResult result = new InitResult();
            result.jigyo = new JigyoInfo();
            result.jigyo.jigyoName = jigyo.Juji_Juji_Jigyo_Name__c;
            result.jigyo.shibuCode = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Code__c;
            result.jigyo.shibuName = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Name__c;
            result.jigyo.basyoName = jigyo.Juji_Juji_Basyo_Master__r?.JujM_Juji_Basyo_Name__c;
            result.jujishaName = jujisha.name;

            // 本人の割当（割当フラグ＝1 または 確定フラグ＝1）の時間帯
            result.ownAssigned = selectOwnAssignments(jigyo.Id, jujisha);

            // 最も早い実施日・最も遅い実施日（実施日の最小値・最大値）。実施日がない場合は null
            AggregateResult agg = [
                SELECT MIN(Juji_Meisai_Jisi_Nengapi__c) minDate, MAX(Juji_Meisai_Jisi_Nengapi__c) maxDate
                FROM Juji_Jigyo_Meisai__c
                WHERE Juji_Meisai_Juji_Jigyo__c = :jigyo.Id
                WITH USER_MODE
            ];
            result.minJisshibi = toDateText((Date) agg.get('minDate'));
            result.maxJisshibi = toDateText((Date) agg.get('maxDate'));
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 画面アクション No.34 一覧表示：5.データ更新 (6) ====================
    // 引数：fromDate・toDate（'yyyy-MM-dd'。表示期間（表示年月の1日〜末日））
    // 戻り値：表示期間内の実施日のリスト
    //   [{ jisshibi, boshuNinzu, startTime, endTime, biko, wariateNinzu,
    //      timeSlots: [{ startTime, endTime, count, wariateNinzu }] }]
    @AuraEnabled
    public static List<Map<String, Object>> getDays(
        String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, String fromDate, String toDate
    ) {
        try {
            Juji_Jigyo__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            Date fromD = Date.valueOf(fromDate);
            Date toD = Date.valueOf(toDate);

            // ① 従事事業明細（実施日）の取得（実施日の昇順）
            List<Juji_Jigyo_Meisai__c> recs = [
                SELECT Juji_Meisai_Jisi_Nengapi__c, Juji_Meisai_Bosyu_Ninzu__c, Juji_Meisai_Kaisi_Jikoku__c,
                    Juji_Meisai_Syuryo_Jikoku__c, Juji_Meisai_Biko__c, Juji_Meisai_JisshiJikantai_Meisai__c
                FROM Juji_Jigyo_Meisai__c
                WHERE Juji_Meisai_Juji_Jigyo__c = :jigyo.Id
                AND Juji_Meisai_Jisi_Nengapi__c >= :fromD
                AND Juji_Meisai_Jisi_Nengapi__c <= :toD
                WITH USER_MODE
                ORDER BY Juji_Meisai_Jisi_Nengapi__c
            ];

            // ② 従事事業割当（確定）の取得（日付ごと）
            Map<Date, List<Assignment>> assignments = selectConfirmedAssignments(jigyo.Id, fromD, toD);

            List<Map<String, Object>> days = new List<Map<String, Object>>();
            for (Juji_Jigyo_Meisai__c rec : recs) {
                List<Assignment> dayAssignments = assignments.containsKey(rec.Juji_Meisai_Jisi_Nengapi__c)
                    ? assignments.get(rec.Juji_Meisai_Jisi_Nengapi__c)
                    : new List<Assignment>();
                DayInfo day = new DayInfo();
                day.jisshibi = toDateText(rec.Juji_Meisai_Jisi_Nengapi__c);
                day.boshuNinzu = rec.Juji_Meisai_Bosyu_Ninzu__c;
                day.startTime = toTimeText(rec.Juji_Meisai_Kaisi_Jikoku__c);
                day.endTime = toTimeText(rec.Juji_Meisai_Syuryo_Jikoku__c);
                day.biko = rec.Juji_Meisai_Biko__c;
                // 割当人数（3.表示ラベル No.63）日付行：その日の割当の件数
                day.wariateNinzu = dayAssignments.size();
                // 時間帯行（開始時間の昇順）。割当人数：その時間帯を含む割当の件数
                day.timeSlots = new List<SlotInfo>();
                for (SlotInfo slot : sortSlots(parseSlots(rec.Juji_Meisai_JisshiJikantai_Meisai__c))) {
                    slot.wariateNinzu = 0;
                    for (Assignment a : dayAssignments) {
                        if (a.slotKeys.contains(slotKey(slot.startTime, slot.endTime))) {
                            slot.wariateNinzu++;
                        }
                    }
                    day.timeSlots.add(slot);
                }
                days.add(toMap(day));
            }
            return days;
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 画面アクション No.30 保存：4.入力チェック No.23 ====================
    // 一括割当実行中の場合はエラー
    @AuraEnabled
    public static void checkSave(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        try {
            Juji_Jigyo__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            Juj_CommonController.checkIkkatsuExecution(jigyo.Id, NO_CHECK_KEYS);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== Selector ====================
    // 従事事業（3項目のいずれかが未入力の場合はクエリを発行しない）
    private static Juji_Jigyo__c selectJigyo(String jigyoNo, String basyoNo, String nendo) {
        if (String.isBlank(jigyoNo) || String.isBlank(basyoNo) || String.isBlank(nendo)) {
            return null;
        }
        List<Juji_Jigyo__c> recs = [
            SELECT Id, Juji_Juji_Jigyo_Name__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Code__c,
                Juji_Jimusyo_Hojin__r.Jims_Sibu_Name__c, Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_Name__c
            FROM Juji_Jigyo__c
            WHERE Juji_Juji_Jigyo_No__c = :jigyoNo
            AND Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c = :basyoNo
            AND Juji_Jisi_Nendo__c = :nendo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事者（会員 → 相談員の順に取得。取得できない場合は null）
    private static Jujisha findJujisha(String jujishaNo) {
        if (String.isBlank(jujishaNo)) {
            return null;
        }
        List<Contact> members = [
            SELECT Id, Name FROM Contact WHERE Kaii_Toroku_No__c = :jujishaNo WITH USER_MODE LIMIT 1
        ];
        if (!members.isEmpty()) {
            Jujisha j = new Jujisha();
            j.memberId = members[0].Id;
            j.name = members[0].Name;
            return j;
        }
        List<Soudanin_Master__c> sodanins = [
            SELECT Id, SouM_Sodanin_Name__c
            FROM Soudanin_Master__c
            WHERE SouM_Sodanin_No__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!sodanins.isEmpty()) {
            Jujisha j = new Jujisha();
            j.sodaninId = sodanins[0].Id;
            j.name = sodanins[0].SouM_Sodanin_Name__c;
            return j;
        }
        return null;
    }

    // ==================== 割当（従事事業割当）====================
    // ※ 1件＝ある日に1人を割り当てたもの。従事事業の主従子オブジェクトで、会員・相談員を参照する。
    //   仮割当＝割当フラグ＝1、確定＝確定フラグ＝1。実施時間帯明細に従事する時間帯を JSON で保持する。

    // 画面アクション No.21 本人の割当（仮割当を含む）の時間帯（日付ごと）
    @TestVisible
    private static List<KanoubiDate> selectOwnAssignments(Id jigyoId, Jujisha jujisha) {
        Id memberId = jujisha.memberId;
        Id sodaninId = jujisha.sodaninId;
        List<Juji_Jigyo_Wariate__c> recs = [
            SELECT Wari_Juji_Nengapi__c, Wari_JisshiJikantai_Meisai__c
            FROM Juji_Jigyo_Wariate__c
            WHERE Wari_Juji_Jigyo__c = :jigyoId
            AND Wari_Kaiin__c = :memberId
            AND Wari_Soudanin_Master__c = :sodaninId
            AND (Wari_Wriate_Flag__c = :FLAG_ON OR Wari_Kakutei_Flag__c = :FLAG_ON)
            WITH USER_MODE
            ORDER BY Wari_Juji_Nengapi__c
        ];
        // 同じ日に複数件ある場合は時間帯をまとめる
        Map<Date, Set<String>> keysByDate = new Map<Date, Set<String>>();
        for (Juji_Jigyo_Wariate__c rec : recs) {
            if (!keysByDate.containsKey(rec.Wari_Juji_Nengapi__c)) {
                keysByDate.put(rec.Wari_Juji_Nengapi__c, new Set<String>());
            }
            for (SlotInfo slot : parseSlots(rec.Wari_JisshiJikantai_Meisai__c)) {
                keysByDate.get(rec.Wari_Juji_Nengapi__c).add(slotKey(slot.startTime, slot.endTime));
            }
        }
        List<KanoubiDate> result = new List<KanoubiDate>();
        for (Date d : keysByDate.keySet()) {
            KanoubiDate k = new KanoubiDate();
            k.kanoubiDate = toDateText(d);
            k.timeSlots = new List<TimeSlotKey>();
            for (String key : keysByDate.get(d)) {
                TimeSlotKey slot = new TimeSlotKey();
                slot.startTime = key.substringBefore('-');
                slot.endTime = key.substringAfter('-');
                k.timeSlots.add(slot);
            }
            result.add(k);
        }
        return result;
    }

    // 5.データ更新 (6)② 表示期間内の確定した割当（日付ごと）
    @TestVisible
    private static Map<Date, List<Assignment>> selectConfirmedAssignments(Id jigyoId, Date fromD, Date toD) {
        Map<Date, List<Assignment>> result = new Map<Date, List<Assignment>>();
        for (Juji_Jigyo_Wariate__c rec : [
            SELECT Wari_Juji_Nengapi__c, Wari_JisshiJikantai_Meisai__c
            FROM Juji_Jigyo_Wariate__c
            WHERE Wari_Juji_Jigyo__c = :jigyoId
            AND Wari_Juji_Nengapi__c >= :fromD
            AND Wari_Juji_Nengapi__c <= :toD
            AND Wari_Kakutei_Flag__c = :FLAG_ON
            WITH USER_MODE
        ]) {
            Assignment a = new Assignment();
            for (SlotInfo slot : parseSlots(rec.Wari_JisshiJikantai_Meisai__c)) {
                a.slotKeys.add(slotKey(slot.startTime, slot.endTime));
            }
            if (!result.containsKey(rec.Wari_Juji_Nengapi__c)) {
                result.put(rec.Wari_Juji_Nengapi__c, new List<Assignment>());
            }
            result.get(rec.Wari_Juji_Nengapi__c).add(a);
        }
        return result;
    }

    // ==================== 変換 ====================
    // 実施時間帯明細（JSON）→ 時間帯リスト（未設定・形式不正の場合は空。使用しない項目は無視する）
    @TestVisible
    private static List<SlotInfo> parseSlots(String value) {
        if (String.isBlank(value)) {
            return new List<SlotInfo>();
        }
        try {
            return (List<SlotInfo>) JSON.deserialize(value, List<SlotInfo>.class);
        } catch (JSONException e) {
            return new List<SlotInfo>();
        }
    }

    // 開始時間の昇順に並べる（'HH:mm' の文字列比較）
    private static List<SlotInfo> sortSlots(List<SlotInfo> slots) {
        List<String> keys = new List<String>();
        Map<String, SlotInfo> byKey = new Map<String, SlotInfo>();
        for (Integer i = 0; i < slots.size(); i++) {
            String k = slots[i].startTime + '|' + slots[i].endTime + '|' + String.valueOf(i).leftPad(4, '0');
            keys.add(k);
            byKey.put(k, slots[i]);
        }
        keys.sort();
        List<SlotInfo> sorted = new List<SlotInfo>();
        for (String k : keys) {
            sorted.add(byKey.get(k));
        }
        return sorted;
    }

    // 時間帯の同一判定キー（開始時間＋終了時間）
    @TestVisible
    private static String slotKey(String startTime, String endTime) {
        return startTime + '-' + endTime;
    }

    private static String toDateText(Date d) {
        return d == null ? null : String.valueOf(d); // 'yyyy-MM-dd'
    }

    // 開始時間・終了時間（時間型）→ 'HH:mm'（時間型以外の値はそのまま文字列にする）
    @TestVisible
    private static String toTimeText(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Time) {
            Time t = (Time) value;
            return Datetime.newInstance(Date.today(), t).format(TIME_FORMAT);
        }
        return String.valueOf(value);
    }

    private static Map<String, Object> toMap(Object dto) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto));
    }

    // ==================== 例外 ====================
    public class JujiOboException extends Exception {
        public String messageId;
    }

    private static JujiOboException error(List<String> msg) {
        JujiOboException e = new JujiOboException(msg[1]);
        e.messageId = msg[0];
        return e;
    }

    private static AuraHandledException toAuraException(JujiOboException e) {
        AuraHandledException ae = new AuraHandledException(e.getMessage());
        ae.setMessage(e.getMessage());
        return ae;
    }

    // ==================== DTO（クラス内部でのみ使用） ====================
    public class InitResult {
        public JigyoInfo jigyo;
        public String jujishaName;
        public List<KanoubiDate> ownAssigned;
        public String minJisshibi;
        public String maxJisshibi;
    }

    public class JigyoInfo {
        public String jigyoName;
        public String shibuCode;
        public String shibuName;
        public String basyoName;
    }

    // 従事者（サーバ内部でのみ使用）
    public class Jujisha {
        public Id memberId;
        public Id sodaninId;
        public String name;
    }

    // 実施日（日付行）
    public class DayInfo {
        public String jisshibi; // 'yyyy-MM-dd'
        public Decimal boshuNinzu;
        public String startTime;
        public String endTime;
        public String biko;
        public Integer wariateNinzu;
        public List<SlotInfo> timeSlots;
    }

    // 時間帯（従事事業明細の実施時間帯明細の1要素。count＝募集人数）
    public class SlotInfo {
        public String startTime;
        public String endTime;
        public Integer count;
        public Integer wariateNinzu;
    }

    // 従事可能日（日付と時間帯）
    public class KanoubiDate {
        public String kanoubiDate;
        public List<TimeSlotKey> timeSlots;
    }

    public class TimeSlotKey {
        public String startTime;
        public String endTime;
    }

    // 割当（1件＝ある日に1人。slotKeys は実施時間帯明細の時間帯キー）
    public class Assignment {
        public Set<String> slotKeys = new Set<String>();
    }
}
