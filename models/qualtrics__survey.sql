with survey as (
-- contians survey version + associated internal-user data
    select *
    from {{ ref('int_qualtrics__survey') }}
),

responses as (

    select *
    from {{ var('survey_response') }}
),

question as (

    select *
    from {{ var('question') }}
),

agg_questions as (

    select 
        survey_id,
        source_relation,
        count(distinct question_id) as count_questions
    from question 
    where not coalesce(is_deleted, false)
    group by 1,2
),

agg_responses as (

    {# From https://qualtrics.com/support/survey-platform/distributions-module/distribution-summary/#ChannelCategorization #}
    {% set distribution_channels = ('anonymous', 'social', 'gl', 'qr', 'email', 'smsinvite') %}

    select
        survey_id,
        source_relation,
        avg(duration_in_seconds) as avg_response_duration_in_seconds,
        avg(progress) as avg_survey_progress_pct,
        count(distinct response_id) as count_survey_responses,
        count(distinct case when is_finished then response_id else null end) as count_completed_survey_responses,
        count(distinct 
                case 
                when {{ fivetran_utils.timestamp_diff(first_date="recorded_date", second_date=dbt.current_timestamp(), datepart="day") }} <= 30 then response_id
                else null end) as count_survey_responses_30d,
        count(distinct 
                case 
                when is_finished and {{ fivetran_utils.timestamp_diff(first_date="recorded_date", second_date=dbt.current_timestamp(), datepart="day") }} <= 30 then response_id
                else null end) as count_completed_survey_responses_30d,
        
        -- pivot out distribution channel responses
        {% for distribution_channel in distribution_channels %}
        count(distinct 
                case 
                when distribution_channel = '{{ distribution_channel }}' then response_id
                else null end) as count_{{ distribution_channel }}_survey_responses,
        count(distinct 
                case 
                when distribution_channel = '{{ distribution_channel }}' and is_finished then response_id
                else null end) as count_{{ distribution_channel }}_completed_survey_responses,
        {% endfor %}

        count(distinct case 
                when distribution_channel not in {{ distribution_channels }} then response_id
                else null end) as count_uncategorized_survey_responses,
        count(distinct case 
                when is_finished and distribution_channel not in {{ distribution_channels }} then response_id
                else null end) as count_uncategorized_completed_survey_responses

    from responses 
    group by 1,2
),

survey_join as (

    select
        survey.*,
        agg_questions.count_questions,

        agg_responses.avg_response_duration_in_seconds,
        agg_responses.avg_survey_progress_pct,
        agg_responses.count_survey_responses,
        agg_responses.count_completed_survey_responses,
        agg_responses.count_survey_responses_30d,
        agg_responses.count_completed_survey_responses_30d,

        -- distribution channels
        agg_responses.count_anonymous_survey_responses,
        agg_responses.count_anonymous_completed_survey_responses,
        agg_responses.count_social_survey_responses as count_social_media_survey_responses,
        agg_responses.count_social_completed_survey_responses as count_social_media_completed_survey_responses,
        agg_responses.count_gl_survey_responses as count_personal_link_survey_responses,
        agg_responses.count_gl_completed_survey_responses as count_personal_link_completed_survey_responses,
        agg_responses.count_qr_survey_responses as count_qr_code_survey_responses,
        agg_responses.count_qr_completed_survey_responses as count_qr_code_completed_survey_responses,
        agg_responses.count_email_survey_responses,
        agg_responses.count_email_completed_survey_responses,
        agg_responses.count_smsinvite_survey_responses,
        agg_responses.count_smsinvite_completed_survey_responses,
        agg_responses.count_uncategorized_survey_responses,
        agg_responses.count_uncategorized_completed_survey_responses

    from survey 
    left join agg_questions
        on survey.survey_id = agg_questions.survey_id
        and survey.source_relation = agg_questions.source_relation
    left join agg_responses
        on survey.survey_id = agg_responses.survey_id
        and survey.source_relation = agg_responses.source_relation
)

select *
from survey_join