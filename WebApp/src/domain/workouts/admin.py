from django.contrib import admin

from .models import (
    Sport, MuscleGroup, WorkoutFolder, Exercise,
    WorkoutPlan, WorkoutDay, WorkoutExercise,
)


@admin.register(Sport)
class SportAdmin(admin.ModelAdmin):
    list_display = ('name', 'slug', 'category', 'order', 'is_system', 'created_by')
    list_filter = ('category', 'is_system')
    search_fields = ('name', 'slug')
    ordering = ('order', 'name')
    prepopulated_fields = {'slug': ('name',)}


@admin.register(MuscleGroup)
class MuscleGroupAdmin(admin.ModelAdmin):
    list_display = ('name', 'slug', 'region', 'color_token', 'order')
    list_filter = ('region',)
    search_fields = ('name', 'slug')
    ordering = ('region', 'order')
    prepopulated_fields = {'slug': ('name',)}


@admin.register(WorkoutFolder)
class WorkoutFolderAdmin(admin.ModelAdmin):
    list_display = ('title', 'coach', 'label_text', 'label_color', 'order')
    list_filter = ('coach',)
    search_fields = ('title', 'label_text')
    ordering = ('coach', 'order')


@admin.register(Exercise)
class ExerciseAdmin(admin.ModelAdmin):
    list_display = (
        'name', 'is_custom', 'created_by',
        'target_muscle_group', 'exercise_classification',
        'updated_at',
    )
    list_filter = ('is_custom', 'difficulty_level', 'body_region')
    search_fields = ('name', 'target_muscle_group', 'primary_muscle')
    filter_horizontal = ('sports', 'primary_muscles', 'secondary_muscles')
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        ('Identificazione', {
            'fields': ('name', 'slug', 'cover_image', 'video_url', 'is_custom', 'created_by'),
        }),
        ('Tassonomia normalizzata', {
            'fields': ('sports', 'primary_muscles', 'secondary_muscles'),
        }),
        ('Tassonomia legacy (testo)', {
            'classes': ('collapse',),
            'fields': (
                'target_muscle_group', 'primary_muscle', 'secondary_muscle',
                'equipment', 'movement_pattern_1', 'movement_pattern_2',
                'body_region', 'exercise_classification', 'difficulty_level',
            ),
        }),
        ('Meta', {
            'fields': ('coach_notes', 'created_at', 'updated_at'),
        }),
    )


@admin.register(WorkoutPlan)
class WorkoutPlanAdmin(admin.ModelAdmin):
    list_display = ('title', 'coach', 'plan_kind', 'sport', 'folder',
                    'status', 'duration_weeks', 'updated_at')
    list_filter = ('plan_kind', 'status', 'sport', 'is_template')
    search_fields = ('title', 'coach__user__email')
    raw_id_fields = ('coach', 'folder', 'sport')


@admin.register(WorkoutDay)
class WorkoutDayAdmin(admin.ModelAdmin):
    list_display = ('workout_plan', 'day_order', 'day_name')
    raw_id_fields = ('workout_plan',)


@admin.register(WorkoutExercise)
class WorkoutExerciseAdmin(admin.ModelAdmin):
    list_display = ('exercise', 'workout_day', 'order_index',
                    'set_count', 'rep_range', 'execution_type')
    list_filter = ('execution_type',)
    raw_id_fields = ('workout_day', 'exercise', 'alternative_exercise')
