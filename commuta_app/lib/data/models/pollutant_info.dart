import '../../core/utils/daqi_utils.dart';

/// Static reference content for the device-metric info sheets shown
/// when the user taps (i) on a metric card.
///
/// One class per pollutant / index, each exposing:
///   • [description]                    — "What is …?" body copy
///   • [healthAdviceForBand(DaqiBand)]  — 4-band health guidance
///
/// Sources (paraphrased, except where the copy was authored directly):
///   • WHO Global Air Quality Guidelines (2021)
///   • Defra & COMEAP — UK DAQI, PM emissions statistics
///   • Imperial College London — Environmental Research Group;
///     Smith et al. (2020), "PM2.5 on the London Underground",
///     Environment International.
///   • Sensirion SGP41 — underlying sensor for the VOC Index and NOx
///     Index metrics; both are relative indices (1–500) computed
///     against a rolling background the sensor learns from the user's
///     environment, not absolute concentrations.
///
/// Body text is rendered by `_BodyText` in metric_info_sheet.dart,
/// which supports `**bold**` for inline emphasis and `\n\n` for
/// paragraph breaks.
///
/// Health advice is resolved from the current DAQI band at info-sheet
/// open time and does not dynamically re-derive if the reading's band
/// changes while the sheet is open — matching the UK DAQI card's
/// existing behaviour. The header value, colour and scale marker still
/// update live.

// ─────────────────────────────────────────────────────────────────────────────
// PM2.5 — fine particulate matter (≤ 2.5 µm)
// ─────────────────────────────────────────────────────────────────────────────

class Pm25Info {
  Pm25Info._();

  /// "What is PM2.5?" description body. Three paragraphs: what it is,
  /// where it comes from (UK-focused), and the London Underground
  /// context that motivates Commuta.
  static const String description =
      'PM2.5 refers to fine particles up to 2.5 micrometres across — '
      'about one-thirtieth the width of a human hair. They can reach '
      'deep into the lungs and cross into the bloodstream, which is '
      'why they carry the greatest health burden of any air pollutant. '
      'PM2.5 is one of the five pollutants tracked by the UK DAQI.'
      '\n\n'
      'Outdoor sources include traffic exhaust, wood and coal burning, '
      'and industry — plus **non-exhaust road emissions** from brake, '
      'tyre and road-surface wear, which **Defra** now flags as a '
      'growing share of the UK total. The **WHO** annual guideline is '
      '5 µg/m³.'
      '\n\n'
      'On the London Underground, PM2.5 is almost entirely mechanical — '
      'mostly iron oxide from wheel, rail and brake wear. Tunnel levels '
      'can be roughly fifteen times higher than street level, reported '
      "by **Imperial College London's Environmental Research Group**.";

  /// Band-aware "Health recommendation" body.
  ///
  /// Each band opens with a PM2.5-specific framing sentence
  /// emphasising the deep-lung and cardiovascular pathway that
  /// distinguishes PM2.5 from PM10. The guidance that follows is
  /// aligned with COMEAP's DAQI health messages (paraphrased so as
  /// not to duplicate the UK DAQI card verbatim).
  static String healthAdviceForBand(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:
        return 'PM2.5 is low. Everyday outdoor activity is fine, '
            'though bear in mind that population-level evidence points '
            'to health effects even below current guideline '
            'concentrations.';
      case DaqiBand.moderate:
        return 'PM2.5 is moderate. Fine particles can slip past the '
            'airway defences and reach the deep lung, so mildly '
            'elevated days can nudge symptoms in vulnerable people.'
            '\n\n'
            'If you have a lung or heart condition and feel symptoms, '
            'ease back on strenuous outdoor activity. Most other '
            'people can carry on as normal.';
      case DaqiBand.high:
        return 'PM2.5 is high. At this level, exposure over hours can '
            'meaningfully raise short-term cardiovascular and '
            'respiratory risk, on top of the long-term effects.'
            '\n\n'
            'If you have a lung or heart condition, cut back on hard '
            "outdoor exertion — especially if you're already noticing "
            'symptoms. Asthma sufferers may need their reliever '
            'inhaler more often, and older people should take it '
            'easier too.'
            '\n\n'
            'A sore throat, cough or eye irritation is a sign to '
            'slow down.';
      case DaqiBand.veryHigh:
        return 'PM2.5 is very high. Short-term exposure at this level '
            'is linked to hospitalisations for heart and lung disease.'
            '\n\n'
            'Anyone with lung or heart problems, and older adults, '
            'should avoid strenuous physical activity. Asthma '
            'sufferers may need their reliever inhaler more often.'
            '\n\n'
            'Everyone else should reduce outdoor exertion, '
            'particularly if a cough, sore throat or other symptoms '
            'appear.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PM10 — coarse particulate matter (≤ 10 µm)
// ─────────────────────────────────────────────────────────────────────────────

class Pm10Info {
  Pm10Info._();

  /// "What is PM10?" description body. Same three-paragraph structure
  /// as PM2.5: what it is, where it comes from, and how the London
  /// Underground shifts the picture.
  static const String description =
      'PM10 refers to coarse particles up to 10 micrometres across — '
      'about a seventh the width of a human hair. They lodge mostly '
      'in the upper airways and larger bronchi rather than penetrating '
      'deep into the lung. PM10 is one of the five pollutants tracked '
      'by the UK DAQI.'
      '\n\n'
      'Outdoor sources include construction dust, road-surface wear, '
      'brake and tyre wear, wood burning, and some natural '
      'contributions from soil and sea salt. **Defra** reports that '
      'non-exhaust road emissions are now the biggest single '
      'road-transport source. The **WHO** annual guideline is '
      '15 µg/m³.'
      '\n\n'
      'On the London Underground, the same mechanical wear that '
      'dominates PM2.5 also enriches the coarser PM10 fraction. '
      'Concentrations in tunnels sit well above street level, reported '
      "by **Imperial College London's Environmental Research Group**.";

  /// Band-aware "Health recommendation" body.
  ///
  /// Each band opens with a PM10-specific framing sentence
  /// emphasising upper-airway irritation and asthma — the pathway
  /// that distinguishes PM10 from PM2.5. The guidance that follows
  /// is aligned with COMEAP's DAQI health messages (paraphrased).
  static String healthAdviceForBand(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:
        return 'PM10 is low. Everyday outdoor activity is fine. '
            'Coarser particles are mostly caught by the upper airways '
            'rather than reaching the deep lung.';
      case DaqiBand.moderate:
        return 'PM10 is moderate. Coarser particles tend to deposit '
            'in the nose, throat and larger airways, where they can '
            'irritate sensitive tissues.'
            '\n\n'
            'If you have asthma or another lung or heart condition '
            'and notice symptoms, consider easing off strenuous '
            'outdoor activity. Most other people can carry on as '
            'normal.';
      case DaqiBand.high:
        return 'PM10 is high. Coarser dust can inflame the airways '
            'and set off asthma symptoms, and coughs and throat '
            'irritation are common.'
            '\n\n'
            'People with lung or heart problems should scale back '
            'hard outdoor exertion, especially if already '
            'symptomatic. Asthma sufferers may need their reliever '
            'inhaler more often, and older people should take it '
            'easier too.'
            '\n\n'
            'A cough, sore throat or itchy eyes is a sign to slow '
            'down.';
      case DaqiBand.veryHigh:
        return 'PM10 is very high. Coarser particles at this level '
            'can trigger significant airway irritation and asthma '
            'attacks.'
            '\n\n'
            'Anyone with lung or heart problems, and older adults, '
            'should avoid strenuous physical activity. Asthma '
            'sufferers may need their reliever inhaler more often.'
            '\n\n'
            'Everyone else should reduce outdoor exertion, '
            'particularly if a cough, sore throat or other symptoms '
            'appear.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOC Index — Sensirion SGP41 (dimensionless 1–500)
// ─────────────────────────────────────────────────────────────────────────────

class VocIndexInfo {
  VocIndexInfo._();

  /// "What is VOC Index?" description body.
  ///
  /// Single paragraph — unlike PM2.5/PM10 the VOC Index is a single
  /// unified concept (a Sensirion SGP41 relative index), not a
  /// pollutant with distinct sources / health / Underground context
  /// to split across paragraphs.
  static const String description =
      'The VOC Index shows how the level of volatile organic '
      'compounds (VOCs) around you compares to your typical '
      'background. VOCs are gases released by many everyday sources '
      '— vehicle exhaust, cleaning products, cosmetics, adhesives, '
      'personal care items, air fresheners, and combustion. Rather '
      'than reporting a specific concentration, the sensor learns '
      'what "normal" looks like in your daily environment over the '
      'past 24 hours and shows the deviation from that baseline on '
      'a 1–500 scale. A value of 100 means conditions are typical '
      'for you; higher values mean more VOCs than usual; lower '
      'values mean cleaner air than usual.';

  /// Band-aware "Health recommendation" body.
  ///
  /// Bands align 1:1 with [DaqiUtils.forTvoc] boundaries
  /// (≤ 150 / ≤ 250 / ≤ 400 / > 400). Each band opens with the label
  /// shown on the card pill.
  static String healthAdviceForBand(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:
        return 'Low. The air around you is at your typical '
            'background level. No action needed.';
      case DaqiBand.moderate:
        return "Moderate. A moderate VOC event is detected. Common "
            "causes include nearby cleaning products, cosmetics, "
            "vehicle emissions, or recently painted or furnished "
            "spaces. Short exposures at this level don't typically "
            "cause noticeable effects for most people.";
      case DaqiBand.high:
        return "High. A strong VOC event is present. Prolonged "
            "exposure can cause mild irritation of the eyes, nose, "
            "or throat, or a headache in sensitive individuals. If "
            "you're indoors, improving ventilation helps. If in "
            "transit, the source is often short-lived — a passing "
            "vehicle or recently cleaned space.";
      case DaqiBand.veryHigh:
        return 'Very High. VOC levels are significantly elevated '
            'compared to your background. Prolonged exposure at '
            'this level may cause eye, nose, and throat irritation, '
            'headaches, or dizziness, particularly in children, '
            'older adults, and people with pre-existing respiratory '
            'conditions. Where possible, move to a better-ventilated '
            'area or reduce time in this environment.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOx Index — Sensirion SGP41 (dimensionless 1–500)
// ─────────────────────────────────────────────────────────────────────────────

class NoxIndexInfo {
  NoxIndexInfo._();

  /// "What is NOx Index?" description body. Single paragraph, same
  /// design rationale as [VocIndexInfo].
  static const String description =
      'The NOx Index shows how the level of nitrogen oxides (NOx) '
      'around you compares to your typical background. NOx gases '
      'come mainly from combustion — vehicle engines (especially '
      'diesel), gas cooking and heating, and industrial processes '
      '— and can also be produced in some transit environments. '
      'Rather than reporting a specific concentration, the sensor '
      'learns your daily background level and displays deviations '
      'from it on a 1–500 scale. A value of 1 means no NOx event '
      'is detected; higher values indicate a NOx event of '
      'increasing intensity.';

  /// Band-aware "Health recommendation" body.
  ///
  /// Bands align 1:1 with [DaqiUtils.forNox] boundaries
  /// (≤ 30 / ≤ 150 / ≤ 300 / > 300). The pill labels on the metric
  /// card are Baseline / Mild event / Moderate event / Strong event
  /// rather than the generic Low / Moderate / High / Very High — the
  /// switch below maps each severity band to its corresponding pill
  /// label so the sheet and card stay in sync:
  ///   low       → Baseline
  ///   moderate  → Mild event
  ///   high      → Moderate event
  ///   veryHigh  → Strong event
  static String healthAdviceForBand(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:
        return "Baseline. No NOx event is detected. You're at your "
            "typical background level.";
      case DaqiBand.moderate:
        return 'Mild event. A mild oxidising gas event is detected. '
            'Common sources include nearby traffic, gas cooking, or '
            'transit environments where combustion or mechanical '
            'wear can produce oxidising particles. Short exposures '
            'at this level are generally harmless.';
      case DaqiBand.high:
        return 'Moderate event. A notable NOx event is present, '
            'likely from combustion sources nearby such as busy '
            'traffic. Prolonged exposure at this level can irritate '
            'the airways in sensitive individuals.';
      case DaqiBand.veryHigh:
        return 'Strong event. A strong NOx event is detected. NOx '
            'can aggravate asthma and other respiratory conditions '
            'and has been linked to increased respiratory symptoms '
            'during short-term exposure. If you have asthma, chronic '
            'respiratory conditions, or cardiovascular sensitivity, '
            'consider reducing time in this environment where '
            'possible.';
    }
  }
}